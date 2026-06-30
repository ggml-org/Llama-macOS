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

/// Manages the llama-server binary process lifecycle and health monitoring.
///
/// The server runs *continuously*: it's started once at app launch (see
/// `ensureCLIThenStartServer` in `LlamaApp`) and stays up in router mode to host
/// the webui and serve requests even with no model loaded -- models load/unload
/// in-place, the process doesn't. So callers can assume it's running; don't add
/// "start it if it's down" logic to open the webui or reach an endpoint.
@MainActor
class LlamaServer {
  /// Singleton instance for app-wide server management
  static let shared = LlamaServer()

  /// Default port the server listens on -- matches llama.cpp's own default,
  /// so URLs the app prints line up with a plain `llama serve`.
  nonisolated static let defaultPort = 8080

  /// The effective port: the user's override if set, else the default.
  nonisolated static var port: Int { UserSettings.serverPort ?? defaultPort }

  /// Whether `port` is free to bind on localhost right now. Used to validate a
  /// user-chosen port before saving it, so a conflict is caught at the point of
  /// the action rather than as an opaque server failure later. (Best-effort:
  /// the port could still get taken between this check and the server binding.)
  nonisolated static func isPortAvailable(_ port: Int) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return true }  // can't probe -- don't block the user
    defer { close(fd) }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(port).bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    // No SO_REUSEADDR: we want bind to fail if something already holds the port.
    let result = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    return result == 0
  }

  /// Returns the host string for server URLs.
  /// If network bind address is set, uses that (resolving 0.0.0.0 to the actual local IP).
  /// Otherwise defaults to "localhost".
  static var resolvedHost: String {
    if let bindAddr = UserSettings.networkBindAddress {
      return bindAddr == "0.0.0.0"
        ? (getLocalIpAddress() ?? "0.0.0.0")
        : bindAddr
    }
    return "localhost"
  }

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
  var modelStatuses: [String: ModelLoadState] = [:] {
    didSet { NotificationCenter.default.post(name: .LBModelStatusDidChange, object: self) }
  }
  /// The ID of the currently active model, derived from `modelStatuses`.
  /// A model counts as active while it's loaded or in the process of loading.
  /// `--models-max 1` guarantees at most one such model.
  var activeModelId: String? {
    modelStatuses.first { $0.value == .loaded || $0.value == .loading }?.key
  }
  var memoryUsageMb: Double = 0 {
    didSet { NotificationCenter.default.post(name: .LBServerMemoryDidChange, object: self) }
  }

  private var memoryTask: Task<Void, Never>?

  // Store observer token for proper cleanup
  private var settingsObserver: NSObjectProtocol?

  init() {
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

  /// A fully-resolved description of the `llama serve` invocation: the binary
  /// path, its arguments, and the env vars we layer on top of the inherited
  /// environment. `start()` builds one of these and runs it; the settings UI
  /// renders one as a shell command so users can see exactly what's launched
  /// (and so changing a setting visibly changes the command).
  struct LaunchSpec {
    let executablePath: String
    let arguments: [String]
    /// Only the env vars *we* set -- not the full inherited environment.
    let env: [(key: String, value: String)]

    /// Renders the spec as a copy-pasteable shell command: the env-var
    /// assignments, then the binary and its arguments, all shell-quoted, on a
    /// single line. This is what gets copied to the clipboard.
    var shellCommand: String {
      let envPart = env.map { "\($0.key)=\(Self.quote($0.value))" }
      let cmdPart = [executablePath] + arguments.map(Self.quote)
      return (envPart + cmdPart).joined(separator: " ")
    }

    /// A reading-friendly rendering of the same command: the env vars as plain
    /// `export` statements up top (each flush-left on its own line), a blank
    /// line, then the invocation -- the binary and subcommand on one line, with
    /// each `--flag` (grouped with its value) hanging-indented below. Paths are
    /// abbreviated to `$HOME` and quoted with *double* quotes, so the block
    /// stays paste-and-run correct (unlike `~` or single quotes, which wouldn't
    /// expand `$HOME` inside the spaced preset path). Meant for the eye; the
    /// clipboard still gets the compact single-line `shellCommand`.
    var displayCommand: String {
      // Group arguments so a `--flag` carries its following value(s) on one
      // line; bare positional args (like `serve`) stand alone.
      var lines: [String] = []
      var idx = arguments.startIndex
      while idx < arguments.endIndex {
        let arg = arguments[idx]
        let next = arguments.index(after: idx)
        if arg.hasPrefix("-"), next < arguments.endIndex,
          !arguments[next].hasPrefix("-")
        {
          lines.append("\(arg) \(Self.displayValue(arguments[next]))")
          idx = arguments.index(after: next)
        } else {
          lines.append(Self.displayValue(arg))
          idx = next
        }
      }

      // The binary leads the command line. Any leading positional args (the
      // subcommand, e.g. `serve`) ride on that same line -- `llama serve` reads
      // as one unit -- and the flags follow, one per line.
      var firstLine = Self.displayValue(executablePath)
      while let head = lines.first, !head.hasPrefix("-") {
        firstLine += " " + head
        lines.removeFirst()
      }

      // Env vars as standalone `export` statements -- each flush-left on its
      // own line, no continuation backslash, so the setup reads as a calm list
      // separate from the invocation below.
      let exportLines = env.map { "export \($0.key)=\(Self.displayValue($0.value))" }

      // The invocation: binary + subcommand on the first line, each flag
      // hanging-indented below, joined by " \<newline>" so it stays runnable.
      let cmdLines = [firstLine] + lines
      let cmdBlock = cmdLines.enumerated().map { i, line in
        let prefix = i == 0 ? "" : "  "
        let suffix = i == cmdLines.count - 1 ? "" : " \\"
        return prefix + line + suffix
      }.joined(separator: "\n")

      // A blank line sets the exports apart from the command they precede
      // (no exports -> no leading blank line).
      return (exportLines.isEmpty ? [cmdBlock] : exportLines + ["", cmdBlock])
        .joined(separator: "\n")
    }

    /// Renders a value for the human-readable `displayCommand`: abbreviates the
    /// home dir to `$HOME`, then quotes with *double* quotes if the value
    /// contains anything the shell would treat specially. Double quotes (vs the
    /// single quotes `shellCommand` uses) are deliberate -- they preserve
    /// spaces yet still let `$HOME` expand, keeping the displayed block runnable.
    private static func displayValue(_ s: String) -> String {
      let home = NSHomeDirectory()
      let abbreviated = s.hasPrefix(home) ? "$HOME" + s.dropFirst(home.count) : s

      // `$` is in the allow-list: it's only ever our own `$HOME`, which we want
      // left unquoted-or-double-quoted so it expands.
      let needsQuote = abbreviated.contains {
        !$0.isLetter && !$0.isNumber && !"-_./=:$".contains($0)
      }
      return needsQuote ? "\"\(abbreviated)\"" : abbreviated
    }

    /// Minimal shell quoting: wraps a token in single quotes only if it
    /// contains characters that the shell would otherwise treat specially.
    private static func quote(_ s: String) -> String {
      guard s.contains(where: { !$0.isLetter && !$0.isNumber && !"-_./=:".contains($0) })
      else { return s }
      return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
  }

  /// An empty dir pointed at by `LLAMA_CACHE` to suppress router mode's
  /// automatic model discovery. Without it, llama-server scans the cache and
  /// lists every GGUF it finds; we manage the model list ourselves via
  /// `--models-preset`. A fixed `/tmp` path keeps the rendered command short
  /// (and matches where we put `--log-file`).
  nonisolated static let emptyCachePath = "/tmp/llama-empty-cache"

  /// Builds the `llama serve` launch spec from the current settings. Pure with
  /// respect to process state -- it only reads settings and the resolved binary
  /// path -- so the settings UI can call it to preview the command. Returns nil
  /// only when no llama binary is installed.
  nonisolated static func buildLaunchSpec() -> LaunchSpec? {
    guard let llamaPath = LlamaBinaries.llamaPath else { return nil }

    let presetsPath = UserSettings.appSupportDir.appendingPathComponent("models.ini").path

    let env = [
      (key: "GGML_METAL_NO_RESIDENCY", value: "1"),
      // Set HF_HUB_CACHE so llama-server can resolve model paths in preset
      (key: "HF_HUB_CACHE", value: UserSettings.hfCacheDirectory.path),
      (key: "LLAMA_CACHE", value: Self.emptyCachePath),
    ]

    var arguments = [
      // `serve` is the `llama` subcommand that replaces the old `llama-server`.
      "serve",
      "--models-preset", presetsPath,
      "--port", String(Self.port),
      "--models-max", "1",
      "--log-file", "/tmp/llama-server.log",
      "--jinja",
      "--spec-default",
      "--fit-target", String(Int(Model.memOverheadMb)),
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

    // User-supplied extra flags come last so they can override the built-ins
    // above, and so the rendered "Server command" preview shows them too.
    arguments.append(contentsOf: UserSettings.customServerArgumentTokens)

    return LaunchSpec(executablePath: llamaPath, arguments: arguments, env: env)
  }

  /// Launches llama-server in Router Mode
  func start() {
    stop()

    // Resolve the launch spec up front; a missing install surfaces as an error.
    guard let spec = Self.buildLaunchSpec() else {
      logger.error("llama binary not found")
      state = .error(.invalidPath("llama"))
      return
    }

    state = .loading

    // Ensure the empty-cache dir referenced by LLAMA_CACHE exists.
    try? FileManager.default.createDirectory(
      atPath: Self.emptyCachePath, withIntermediateDirectories: true)

    // All paths in models.ini are absolute, so CWD is mostly cosmetic —
    // but point it at Application Support so stray relative writes (if any) don't leak into $HOME.
    let workingDirectory = UserSettings.appSupportDir.path

    let process = Process()
    process.executableURL = URL(fileURLWithPath: spec.executablePath)
    process.arguments = spec.arguments
    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

    var environment = ProcessInfo.processInfo.environment
    for (key, value) in spec.env { environment[key] = value }
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
      self.modelStatuses = [:]
      return
    }
    startStatusPolling()
  }

  /// Terminates the currently running llama-server process and resets state
  func stop() {
    // Set to .idle before terminating so the handler knows this is intentional
    memoryUsageMb = 0
    state = .idle

    // Clearing statuses also clears the derived `activeModelId`, so a stopped
    // server never leaves a model showing as loaded in the menu.
    modelStatuses = [:]

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
    return modelStatuses.values.contains(.loaded)
  }

  /// Checks if any model is currently loading
  var isAnyModelLoading: Bool {
    return modelStatuses.values.contains(.loading)
  }

  /// Checks if the server is currently loading
  var isLoading: Bool {
    state == .loading
  }

  /// Checks if the specified model is currently active
  func isActive(model: Model) -> Bool {
    return modelStatuses[model.id] == .loaded
  }

  /// Checks if the specified model is currently loading
  func isLoading(model: Model) -> Bool {
    return modelStatuses[model.id] == .loading
  }

  /// Switch the active model in the UI. In Router Mode, this doesn't restart the server,
  /// but updates what Llama considers the "current" model.
  func loadModel(_ model: Model) {
    if !isRunning && !isLoading {
      start()
    }

    // Optimistically set status to loading for immediate UI feedback. This also
    // makes the model the derived `activeModelId`. Polling updates to .loaded
    // once the server confirms.
    modelStatuses[model.id] = .loading

    Task {
      _ = await api.loadModel(id: model.id)
    }

    logger.info("Requested active model: \(model.displayName)")
  }

  /// Deselects the current model in the UI.
  func unloadModel(_ model: Model) {
    // Optimistically set status to unloaded for immediate UI feedback (which
    // also clears the derived `activeModelId`). Polling confirms once the
    // server acknowledges.
    modelStatuses[model.id] = .unloaded

    Task {
      _ = await api.unloadModel(id: model.id)
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

  private func startStatusPolling() {
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

    // If the server reports a model as sleeping (idle timeout reached), unload it
    // so the UI reflects the freed state. A .sleeping model isn't counted as the
    // active model, so no extra bookkeeping is needed here.
    if let sleepingModelId = newStatuses.first(where: { $0.value == .sleeping })?.key {
      _ = await api.unloadModel(id: sleepingModelId)
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
}
