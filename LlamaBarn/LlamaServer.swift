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

  var state: ServerState = .idle
  var activeModelPath: String?
  var memoryUsageMB: Double = 0

  private var memoryTask: Task<Void, Never>?

  init() {
    libFolderPath = Bundle.main.bundlePath + "/Contents/MacOS/llama-cpp"
  }

  /// Basic validation of required paths
  private func validatePaths(modelPath: String, mmprojPath: String? = nil) throws {
    guard FileManager.default.fileExists(atPath: modelPath) else {
      logger.error("Model file not found: \(modelPath)")
      throw LlamaServerError.invalidPath(modelPath)
    }

    if let mmprojPath = mmprojPath, !FileManager.default.fileExists(atPath: mmprojPath) {
      logger.error("Vision file not found: \(mmprojPath)")
      throw LlamaServerError.invalidPath(mmprojPath)
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

    outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
      let data = fileHandle.availableData
      if data.count == 0 {
        fileHandle.readabilityHandler = nil
      } else {
        if let output = String(data: data, encoding: .utf8) {
          self.logger.info("llama-server: \(output.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)")
        }
      }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
      let data = fileHandle.availableData
      if data.count == 0 {
        fileHandle.readabilityHandler = nil
      } else {
        if let error = String(data: data, encoding: .utf8) {
          self.logger.error("llama-server error: \(error.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)")
        }
      }
    }
  }

  /// Launches llama-server with specified model and configuration
  func start(
    modelName: String,
    modelPath: String,
    mmprojPath: String? = nil,
    extraArgs: [String] = []
  ) {
    let port = Self.defaultPort
    stop()

    // Validate paths
    do {
      try validatePaths(modelPath: modelPath, mmprojPath: mmprojPath)
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

    let llamaServerPath = libFolderPath + "/llama-server"
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: llamaServerPath)

    let env = ["GGML_METAL_NO_RESIDENCY": "1"]
    var arguments = [
      "--model", modelPath,
      "--port", String(port),
      "--alias", modelName,
      "--log-file", "/tmp/llama-server.log",
      "--no-mmap",
    ]

    if let mmprojPath = mmprojPath {
      arguments.append(contentsOf: ["--mmproj", mmprojPath])
    }
    arguments.append(contentsOf: extraArgs)

    let workingDirectory = URL(fileURLWithPath: llamaServerPath).deletingLastPathComponent().path

    // Stop any existing process first
    stopActiveProcess()

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
      }
      return
    }

    guard let process = activeProcess else {
      DispatchQueue.main.async {
        self.state = .error(.launchFailed("Process creation failed"))
        self.activeModelPath = nil
      }
      return
    }

    attachOutputHandlers(for: process)
    startHealthCheck(port: port)
  }

  /// Terminates the currently running llama-server process and resets state
  func stop() {
    guard let process = activeProcess, process.isRunning else {
      resetState()
      return
    }

    // Try graceful termination first
    process.terminate()

    // Give the process a brief moment to terminate gracefully
    DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
      if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
      }
    }

    resetState()
  }

  /// Resets all server state
  private func resetState() {
    cleanUpResources()

    self.activeProcess = nil
    self.state = .idle
    self.activeModelPath = nil
    self.memoryUsageMB = 0
  }

  /// Cleans up all resources including process, pipes, and monitoring tasks
  private func cleanUpResources() {
    stopActiveProcess()
    cleanUpPipes()
    stopHealthCheck()
    stopMemoryMonitoring()
  }

  /// Gracefully terminates the currently running process
  private func stopActiveProcess() {
    guard let process = activeProcess, process.isRunning else { return }

    process.terminate()
    process.waitUntilExit()
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
    start(
      modelName: model.displayName,
      modelPath: model.modelFilePath,
      mmprojPath: model.visionFilePath,
      extraArgs: model.serverArgs
    )
  }

  /// Convenience method to toggle server state using a ModelCatalogEntry
  func toggle(model: ModelCatalogEntry) {
    if activeModelPath == model.modelFilePath {
      stop()
    } else {
      start(model: model)
    }
  }

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
        await MainActor.run {
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
        await MainActor.run {
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
        await MainActor.run {
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

  /// Gets the version of the bundled llama.cpp from stored version file
  func getLlamaCppVersion() -> String {
    guard let url = Bundle.main.url(forResource: "version", withExtension: "txt"),
          let version = try? String(contentsOf: url, encoding: .utf8) else {
      return "unknown"
    }
    
    return version.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  deinit {
    stop()
  }
}
