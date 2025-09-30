import Foundation
import Observation
import os.log

/// Essential errors that can occur during llama-server operations
enum LlamaServerError: Error, LocalizedError {
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
@Observable
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
  private let logger = Logger(subsystem: "LlamaBarn", category: "LlamaServer")

  enum ServerState: Equatable {
    case idle
    case loading
    case running
    case error(LlamaServerError)

    static func == (lhs: ServerState, rhs: ServerState) -> Bool {
      switch (lhs, rhs) {
      case (.idle, .idle), (.loading, .loading), (.running, .running):
        return true
      case (.error(let lhsError), .error(let rhsError)):
        return lhsError.localizedDescription == rhsError.localizedDescription
      default:
        return false
      }
    }
  }

  var state: ServerState = .idle {
    didSet { NotificationCenter.default.post(name: .LBServerStateDidChange, object: self) }
  }
  var activeModelPath: String?
  private(set) var activeContextLength: Int?
  var memoryUsageMB: Double = 0 {
    didSet { NotificationCenter.default.post(name: .LBServerMemoryDidChange, object: self) }
  }

  private var memoryTask: Task<Void, Never>?

  init() {
    libFolderPath = Bundle.main.bundlePath + "/Contents/MacOS/llama-cpp"
  }

  /// Basic validation of required paths
  private func validatePaths(modelPath: String) throws {
    guard FileManager.default.fileExists(atPath: modelPath) else {
      logger.error("Model file not found: \(modelPath)")
      throw LlamaServerError.invalidPath(modelPath)
    }

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

  /// Launches llama-server with specified model and configuration
  func start(
    modelName: String,
    modelPath: String,
    appliedContextLength: Int,
    extraArgs: [String] = []
  ) {
    let port = Self.defaultPort
    stop()

    // Validate paths
    do {
      try validatePaths(modelPath: modelPath)
    } catch let error as LlamaServerError {
      DispatchQueue.main.async {
        self.state = .error(error)
      }
      return
    } catch {
      DispatchQueue.main.async {
        self.state = .error(.launchFailed("Validation failed"))
      }
      return
    }

    state = .loading
    activeModelPath = modelPath
    activeContextLength = appliedContextLength

    let llamaServerPath = libFolderPath + "/llama-server"

    let env = ["GGML_METAL_NO_RESIDENCY": "1"]
    var arguments = [
      "--model", modelPath,
      "--port", String(port),
      "--alias", modelName,
      "--log-file", "/tmp/llama-server.log",
      "--no-mmap",
      "--jinja",
    ]

    // Add batch size optimization for devices with 32+ GB RAM
    let systemMemoryGB = Double(SystemMemory.getMemoryMB()) / 1024.0
    if systemMemoryGB >= 32.0 {
      arguments.append(contentsOf: ["-ub", "2048"])
    }

    // Merge in caller-provided args (may include ctx-size from catalog), but we'll prepend
    // an auto-selected ctx-size later if none is provided.
    arguments.append(contentsOf: extraArgs)

    let workingDirectory = URL(fileURLWithPath: llamaServerPath).deletingLastPathComponent().path

    // Create and configure the new process
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
    let currentModelPath = activeModelPath
    process.terminationHandler = { [weak self] proc in
      guard let self = self, currentModelPath == self.activeModelPath else { return }

      if self.activeProcess == proc {
        self.cleanUpResources()
      }
      DispatchQueue.main.async {
        if currentModelPath == self.activeModelPath {
          if proc.terminationStatus == 0 {
            self.state = .idle
          } else {
            self.state = .error(.launchFailed("Process crashed"))
          }
        }
      }
    }

    do {
      try process.run()
      self.activeProcess = process
    } catch {
      let errorMessage = "Process launch failed: \(error.localizedDescription)"
      logger.error("Failed to launch process: \(error)")
      DispatchQueue.main.async {
        self.state = .error(.launchFailed(errorMessage))
        self.activeModelPath = nil
        self.activeContextLength = nil
      }
      return
    }

    guard let process = activeProcess else {
      DispatchQueue.main.async {
        self.state = .error(.launchFailed("Process creation failed"))
        self.activeModelPath = nil
        self.activeContextLength = nil
      }
      return
    }

    attachOutputHandlers(for: process)
    startHealthCheck(port: port)
  }

  /// Terminates the currently running llama-server process and resets state
  func stop() {
    cleanUpResources()
    activeModelPath = nil
    activeContextLength = nil
    memoryUsageMB = 0
    state = .idle
  }

  /// Cleans up all background resources tied to the server process
  private func cleanUpResources() {
    stopActiveProcess()
    cleanUpPipes()
    stopHealthCheck()
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
    return state == .running
  }

  /// Checks if the server is currently loading
  var isLoading: Bool {
    return state == .loading
  }

  /// Checks if the specified model is currently active
  func isActive(model: ModelCatalogEntry) -> Bool {
    return activeModelPath == model.modelFilePath
  }

  /// Convenience method to start server using a ModelCatalogEntry
  func start(model: ModelCatalogEntry) {
    guard let launch = makeLaunchConfiguration(for: model, requestedContext: nil) else {
      let reason =
        ModelCatalog.incompatibilitySummary(model)
        ?? "insufficient memory for required context"
      DispatchQueue.main.async {
        self.state = .error(.launchFailed(reason))
      }
      return
    }

    start(
      modelName: model.displayName,
      modelPath: model.modelFilePath,
      appliedContextLength: launch.applied,
      extraArgs: launch.args
    )
  }

  /// Convenience method to start server using a ModelCatalogEntry and a specific context length
  func start(model: ModelCatalogEntry, contextLength: Int) {
    let desired = contextLength <= 0 ? model.contextLength : contextLength
    guard let launch = makeLaunchConfiguration(for: model, requestedContext: desired) else {
      let reason =
        ModelCatalog.incompatibilitySummary(
          model, contextLengthTokens: Double(model.contextLength))
        ?? "insufficient memory for requested context"
      DispatchQueue.main.async {
        self.state = .error(.launchFailed(reason))
      }
      return
    }

    start(
      modelName: model.displayName,
      modelPath: model.modelFilePath,
      appliedContextLength: launch.applied,
      extraArgs: launch.args
    )
  }

  private func makeLaunchConfiguration(
    for model: ModelCatalogEntry,
    requestedContext: Int?
  ) -> (applied: Int, args: [String])? {
    let sanitizedArgs = Self.removeContextArguments(from: model.serverArgs)
    guard
      let safeContext = ModelCatalog.safeContextLength(
        for: model, desiredTokens: requestedContext)
    else {
      logger.error("No safe context length for model \(model.displayName, privacy: .public)")
      return nil
    }
    let args = ["-c", String(safeContext)] + sanitizedArgs
    return (safeContext, args)
  }

  private static func removeContextArguments(from args: [String]) -> [String] {
    var result: [String] = []
    var skipNext = false
    for arg in args {
      if skipNext {
        skipNext = false
        continue
      }
      if arg == "-c" || arg == "--ctx-size" {
        skipNext = true
        continue
      }
      if arg.hasPrefix("--ctx-size=") {
        continue
      }
      result.append(arg)
    }
    return result
  }

  // Removed: startWithMaxContext(model:) — not used by current UI.
  // Removed: toggle(model:) — UI calls start/stop explicitly.

  private func cleanUpPipes() {
    outputPipe?.fileHandleForReading.readabilityHandler = nil
    errorPipe?.fileHandleForReading.readabilityHandler = nil
    try? outputPipe?.fileHandleForReading.close()
    try? errorPipe?.fileHandleForReading.close()
    outputPipe = nil
    errorPipe = nil
  }

  private func startHealthCheck(port: Int) {
    stopHealthCheck()

    healthCheckTask = Task {
      // Try for up to 30 seconds with 2-second intervals
      for _ in 1...15 {
        if Task.isCancelled { return }

        if await checkHealth(port: port) {
          return
        }

        try await Task.sleep(nanoseconds: 2_000_000_000)
      }

      // Health check failed
      if !Task.isCancelled {
        _ = await MainActor.run {
          if self.state != .idle {
            self.state = .error(.healthCheckFailed)
          }
        }
      }
    }
  }

  private func stopHealthCheck() {
    healthCheckTask?.cancel()
    healthCheckTask = nil
  }

  private func checkHealth(port: Int) async -> Bool {
    guard let url = URL(string: "http://localhost:\(port)/health") else { return false }

    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = 5.0

      let (_, response) = try await URLSession.shared.data(for: request)

      if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
        let memoryValue = getMemoryUsageMB()
        _ = await MainActor.run {
          if self.state != .idle {
            self.state = .running
            self.memoryUsageMB = memoryValue
            self.startMemoryMonitoring()
          }
        }
        return true
      }
    } catch {}

    return false
  }

  private func startMemoryMonitoring() {
    stopMemoryMonitoring()

    memoryTask = Task { [weak self] in
      guard let self = self else { return }

      while !Task.isCancelled {
        guard await MainActor.run(body: { self.state }) == .running else {
          break
        }

        let memoryValue = self.getMemoryUsageMB()
        _ = await MainActor.run {
          self.memoryUsageMB = memoryValue
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
  func getMemoryUsageMB() -> Double {
    guard let process = activeProcess, process.isRunning else { return 0 }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/footprint")
    task.arguments = ["-s", String(process.processIdentifier)]

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

  // Removed: getLlamaCppVersion() — AppMenuController reads version directly.

  deinit {
    stop()
  }
}
