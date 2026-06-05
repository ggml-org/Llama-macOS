import Foundation
import os.log

/// Observable owner of the app-owned CLI install. Holds the install `state` so
/// the menu can surface a "setting up…" banner and a retry affordance, and
/// drives `LlamaInstaller` off the UI.
///
/// The install itself is silent (no permission prompt): it writes only to
/// `~/.installama` / `~/.local/bin`, needs no privilege escalation, and is part
/// of the app's "it just works" setup -- but it's never opaque, hence the state.
@MainActor
final class LlamaInstallManager {
  static let shared = LlamaInstallManager()

  private let logger = Logger(subsystem: Logging.subsystem, category: "LlamaInstallManager")

  enum State: Equatable {
    /// Not installing -- either a binary is present, or we haven't needed to.
    case idle
    /// Downloading/installing the app-owned binary.
    case installing
    /// The install failed; `message` is user-facing. Retry via `install()`.
    case failed(message: String)
  }

  private(set) var state: State = .idle {
    didSet {
      guard state != oldValue else { return }
      NotificationCenter.default.post(name: .LBCLIInstallStateDidChange, object: self)
    }
  }

  /// Ensures a usable `llama` binary exists, installing the app-owned one if
  /// none is found. Returns true if a binary is available afterward.
  @discardableResult
  func ensureInstalled() async -> Bool {
    if case .missing = LlamaBinaries.resolve() {
      return await install()
    }
    state = .idle
    return true
  }

  /// Installs (or reinstalls) the app-owned binary, driving `state`. Also the
  /// retry entry point. Returns true on success.
  @discardableResult
  func install() async -> Bool {
    state = .installing
    do {
      try await LlamaInstaller.installLatest()
      logger.info("Installed the app-owned llama CLI")
      state = .idle
      return true
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      logger.error("CLI install failed: \(message, privacy: .public)")
      state = .failed(message: message)
      return false
    }
  }
}
