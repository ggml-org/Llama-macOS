import Foundation
import os.log

/// Essential errors that can occur during llama-server operations
enum LlamaServerError: Error, LocalizedError, Equatable {
  case launchFailed(String)
  case healthCheckFailed
  case invalidPath(String)

  var errorDescription: String? {
    switch self {
    case .launchFailed(let reason):
      return "Failed to start server: \(reason)"
    case .healthCheckFailed:
      return "Server failed to respond"
    case .invalidPath(let path):
      return "Invalid file: \(path)"
    }
  }
}

/// Manages the llama-server binary process lifecycle and health monitoring
@MainActor
class LlamaServer {
  /// Singleton instance for app-wide server management
  static let shared = LlamaServer()

  /// Default port for llama-server
  static let defaultPort = 2276

  private let libFolderPath: String
  private var outputPipe: Pipe?
  private var errorPipe: Pipe?
  private var activeProcess: Process?
  private var healthCheckTask: Task<Void, Error>?
  private let logger = Logger(subsystem: Logging.subsystem, category: "LlamaServer")
  private let api = LlamaServerAPI()

  enum ServerState: Equatable {
    case idle
    case loading
    case running
    case error(LlamaServerError)
  }

  var state: ServerState = .idle {
    didSet { NotificationCenter.default.post(name: .LBServerStateDidChange, object: self) }
  }
  var activeModelPath: String?
  var modelStatuses: [String: String] = [:] {
    didSet { NotificationCenter.default.post(name: .LBModelStatusDidChange, object: self) }
  }
  var memoryUsageMb: Double = 0 {
    didSet { NotificationCenter.default.post(name: .LBServerMemoryDidChange, object: self) }
  }

  private var memoryTask: Task<Void, Never>?

  // Store observer token for proper cleanup
  private var settingsObserver: NSObjectProtocol?

  init() {
    libFolderPath = Bundle.main.bundlePath + "/Contents/MacOS/llama-cpp"

    // Listen for settings changes to reload server if needed (e.g. sleep timer)
    settingsObserver = NotificationCenter.default.addObserver(
      forName: .LBUserSettingsDidChange, object: nil, queue: .main
    ) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.reload()
      }
    }
  }

  deinit {
    if let settingsObserver {
      NotificationCenter.default.removeObserver(settingsObserver)
    }
  }

  /// Basic validation of required paths
  private func validatePaths() throws {
    let llamaServerPath = libFolderPath + "/llama-server"
    guard FileManager.default.fileExists(atPath: llamaServerPath) else {
      logger.error("llama-server binary not found: \(llamaServerPath)")
      throw LlamaServerError.invalidPath(llamaServerPath)
    }
  }

  private func attachOutputHandlers(for process: Process) {
    guard let outputPipe = process.standardOutput as? Pipe,
      let errorPipe = process.standardError as? Pipe
    else { return }

    self.outputPipe = outputPipe
    self.errorPipe = errorPipe

    setHandler(for: outputPipe) { message in
      self.logger.info("llama-server: \(message, privacy: .public)")
    }

    setHandler(for: errorPipe) { message in
      self.logger.error("llama-server error: \(message, privacy: .public)")
    }
  }

  private func setHandler(for pipe: Pipe, logMessage: @escaping (String) -> Void) {
    pipe.fileHandleForReading.readabilityHandler = { fileHandle in
      let data = fileHandle.availableData
      guard !data.isEmpty else {
        fileHandle.readabilityHandler = nil
        return
      }

      guard let output = String(data: data, encoding: .utf8) else { return }
      logMessage(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  /// Launches llama-server in Router Mode
  func start() {
    let port = Self.defaultPort
    stop()

    // Validate paths
    do {
      try validatePaths()
    } catch let error as LlamaServerError {
      self.state = .error(error)
      return
    } catch {
      self.state = .error(.launchFailed("Validation failed"))
      return
    }

    state = .loading

    let presetsPath = CatalogEntry.modelStorageDirectory.appendingPathComponent("models.ini").path

    let llamaServerPath = libFolderPath + "/llama-server"

    let env = ["GGML_METAL_NO_RESIDENCY": "1"]

    var arguments = [
      "--models-preset", presetsPath,
      "--port", String(port),
      "--models-max", "1",
      "--log-file", "/tmp/llama-server.log",
      "--jinja",
      "--fit-target", String(Int(CatalogEntry.memOverheadMb)),
    ]

    // Bind to custom address if network exposure is enabled
    if let bindAddress = UserSettings.networkBindAddress {
      arguments.append(contentsOf: ["--host", bindAddress])
    }

    // Unload model from memory when idle
    if UserSettings.sleepIdleTime != .disabled {
      arguments.append(contentsOf: [
        "--sleep-idle-seconds", String(UserSettings.sleepIdleTime.rawValue),
      ])
    }

    let workingDirectory = URL(fileURLWithPath: llamaServerPath).deletingLastPathComponent().path

    let process = Process()
    process.executableURL = URL(fileURLWithPath: llamaServerPath)
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

    var environment = ProcessInfo.processInfo.environment
    for (key, value) in env { environment[key] = value }
    process.environment = environment

    process.standardOutput = Pipe()
    process.standardError = Pipe()

    // Set up termination handler for proper state management
    process.terminationHandler = { [weak self] proc in
      Task { @MainActor in
        guard let self = self else { return }

        // Skip handler if we're already idle (intentional stop) or this is an old process
        guard self.state != .idle else { return }
        guard self.activeProcess == proc else { return }

        self.cleanUpResources()

        if proc.terminationStatus == 0 {
          self.state = .idle
        } else {
          self.state = .error(.launchFailed("Process crashed"))
        }
      }
    }

    do {
      try process.run()
      self.activeProcess = process
      attachOutputHandlers(for: process)
    } catch {
      let errorMessage = "Process launch failed: \(error.localizedDescription)"
      logger.error("Failed to launch process: \(error)")
      self.state = .error(.launchFailed(errorMessage))
      self.activeModelPath = nil
      return
    }
    startStatusPolling(port: port)
  }

  /// Terminates the currently running llama-server process and resets state
  func stop() {
    // Set to .idle before terminating so the handler knows this is intentional
    memoryUsageMb = 0
    state = .idle

    activeModelPath = nil

    cleanUpResources()
  }

  /// Reloads the server (restarts) to pick up changes in configuration (e.g. models list)
  func reload() {
    // Skip reload only if server is idle (never started or intentionally stopped)
    guard state != .idle else { return }
    logger.info("Restarting server to apply configuration changes")

    // Regenerate models.ini before restarting to pick up any setting changes
    // (e.g. context window size) that affect the INI content.
    ModelManager.shared.updateModelsFile()

    start()
  }

  /// Cleans up all background resources tied to the server process
  private func cleanUpResources() {
    stopActiveProcess()
    cleanUpPipes()
    stopStatusPolling()
    stopMemoryMonitoring()
  }

  /// Gracefully terminates the currently running process
  private func stopActiveProcess() {
    guard let process = activeProcess else { return }

    if process.isRunning {
      process.terminate()

      DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
        if process.isRunning {
          kill(process.processIdentifier, SIGKILL)
        }
      }

      process.waitUntilExit()
    }

    activeProcess = nil
  }

  // MARK: - State Helper Methods

  /// Checks if the server is currently running
  var isRunning: Bool {
    state == .running
  }

  /// Checks if any model is currently loaded (not loading)
  var isAnyModelLoaded: Bool {
    return modelStatuses.values.contains { $0 == "loaded" }
  }

  /// Checks if any model is currently loading
  var isAnyModelLoading: Bool {
    return modelStatuses.values.contains { $0 == "loading" }
  }

  /// Checks if the server is currently loading
  var isLoading: Bool {
    state == .loading
  }

  /// Checks if the specified model is currently active
  func isActive(model: CatalogEntry) -> Bool {
    return loadedVariantId(for: model) != nil
  }

  /// Checks if the specified model is currently loading
  func isLoading(model: CatalogEntry) -> Bool {
    return modelStatuses.contains { key, status in
      status == "loading" && (key == model.id || key.hasPrefix(model.id + ":"))
    }
  }

  /// Returns the ID of the currently loaded variant for the given model, if any.
  func loadedVariantId(for model: CatalogEntry) -> String? {
    modelStatuses.first { key, status in
      status == "loaded" && (key == model.id || key.hasPrefix(model.id + ":"))
    }?.key
  }

  /// Switch the active model in the UI. In Router Mode, this doesn't restart the server,
  /// but updates what LlamaBarn considers the "current" model.
  func loadModel(_ model: CatalogEntry) {
    if !isRunning && !isLoading {
      start()
    }

    // Optimistically set status to "loading" for immediate UI feedback.
    // The polling will update to "loaded" once the server confirms.
    modelStatuses[model.id] = "loading"

    Task {
      _ = await api.loadModel(id: model.id)
    }

    // In Router Mode, the model is loaded via the /models/load endpoint.
    // We update local state so the UI knows what's selected.
    self.activeModelPath = model.modelFilePath
    logger.info("Requested active model: \(model.displayName)")
  }

  /// Deselects the current model in the UI.
  func unloadModel(_ model: CatalogEntry) {
    // Optimistically set status to "unloaded" for immediate UI feedback.
    // The polling will confirm once the server acknowledges.
    let idToUnload = loadedVariantId(for: model) ?? model.id
    modelStatuses[idToUnload] = "unloaded"

    Task {
      _ = await api.unloadModel(id: idToUnload)
    }

    if activeModelPath == model.modelFilePath {
      activeModelPath = nil
    }
  }

  func unloadModel() {
    activeModelPath = nil
  }

  private func cleanUpPipes() {
    outputPipe?.fileHandleForReading.readabilityHandler = nil
    errorPipe?.fileHandleForReading.readabilityHandler = nil
    try? outputPipe?.fileHandleForReading.close()
    try? errorPipe?.fileHandleForReading.close()
    outputPipe = nil
    errorPipe = nil
  }

  private func startStatusPolling(port: Int) {
    stopStatusPolling()

    healthCheckTask = Task {
      // Poll /models to detect status.
      while !Task.isCancelled {
        await checkStatus()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
  }

  private func stopStatusPolling() {
    healthCheckTask?.cancel()
    healthCheckTask = nil
  }

  private func checkStatus() async {
    guard let newStatuses = await api.fetchModelStatuses() else { return }

    // Check for sleeping models if any model is loaded.
    // We look for 'loaded' status, and if found, query /props for that model.
    // Since --models-max 1 ensures single model, checking the first loaded one is sufficient.
    if let loadedModelId = newStatuses.first(where: { $0.value == "loaded" })?.key {
      if UserSettings.sleepIdleTime != .disabled {
        let isSleeping = await api.isModelSleeping(id: loadedModelId)
        if isSleeping {
          _ = await api.unloadModel(id: loadedModelId)
          await MainActor.run {
            if self.activeModelPath != nil {
              self.activeModelPath = nil
            }
          }
        }
      }
    }

    await MainActor.run {
      if self.state == .loading {
        self.state = .running
        self.startMemoryMonitoring()
      }
      if self.modelStatuses != newStatuses {
        self.modelStatuses = newStatuses
      }
    }
  }

  private func startMemoryMonitoring() {
    stopMemoryMonitoring()

    memoryTask = Task.detached { [weak self] in
      guard let self = self else { return }

      while !Task.isCancelled {
        let (isRunning, pid) = await MainActor.run {
          (self.state == .running, self.activeProcess?.processIdentifier)
        }

        guard isRunning, let pid = pid else { break }

        let memoryValue = Self.measureMemoryUsageMb(pid: pid)
        await MainActor.run {
          self.memoryUsageMb = memoryValue
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
      }
    }
  }

  private func stopMemoryMonitoring() {
    memoryTask?.cancel()
    memoryTask = nil
  }

  /// Measures the current memory footprint of the llama-server process
  nonisolated static func measureMemoryUsageMb(pid: Int32) -> Double {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/footprint")
    task.arguments = ["-s", String(pid)]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()

    do {
      try task.run()
      task.waitUntilExit()

      guard task.terminationStatus == 0 else { return 0 }

      let output =
        String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      guard let range = output.range(of: "Footprint: ") else { return 0 }

      let components = output[range.upperBound...].components(separatedBy: .whitespaces)
      guard components.count >= 2, let value = Double(components[0]) else { return 0 }

      switch components[1] {
      case "MB": return value
      case "GB": return value * 1024
      case "KB": return value / 1024
      default: return 0
      }
    } catch {
      return 0
    }
  }

  /// Returns the IPv4 address of en0 (primary network interface).
  static func getLocalIpAddress() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?

    // Get linked list of all network interfaces (returns 0 on success)
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    // Ensure memory is freed when function exits
    defer { freeifaddrs(ifaddr) }

    // Walk through linked list of network interfaces
    for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
      let interface = ifptr.pointee

      // Skip non-IPv4 addresses (AF_INET = IPv4, AF_INET6 = IPv6)
      guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

      // Get interface name (e.g., "en0", "en1", "lo0")
      let name = String(cString: interface.ifa_name)

      // Only look for en0 (primary interface on most Macs)
      guard name == "en0" else { continue }

      // Convert socket address to human-readable IP string
      var addr = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      getnameinfo(
        interface.ifa_addr,
        socklen_t(interface.ifa_addr.pointee.sa_len),
        &addr,
        socklen_t(addr.count),
        nil,
        socklen_t(0),
        NI_NUMERICHOST  // Return numeric address (e.g., "192.168.1.5")
      )

      return String(cString: addr)
    }

    return nil
  }

  // Removed: getLlamaCppVersion() — MenuController reads version directly.
}
