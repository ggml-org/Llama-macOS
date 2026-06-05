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
    /// Ready -- a usable binary is present (or we haven't needed to act).
    case idle
    /// Downloading/installing the app-owned binary.
    case installing
    /// The install failed; `message` is user-facing. Retry via `install()`.
    case failed(message: String)
    /// An external (e.g. Homebrew) binary is present but below `minVersion`.
    /// The app can't update it, so it nudges the user to do so. Non-blocking:
    /// the server still runs, since the old binary often works.
    case externalTooOld(version: LlamaVersion)
  }

  private(set) var state: State = .idle {
    didSet {
      guard state != oldValue else { return }
      NotificationCenter.default.post(name: .LBCLIInstallStateDidChange, object: self)
    }
  }

  /// Version of the resolved binary in use, for display (e.g. the menu footer).
  /// Refreshed at launch and after an install; nil until first read or when no
  /// binary is present.
  private(set) var currentVersion: LlamaVersion?

  /// Ensures a usable `llama` binary is available, acting on its status:
  /// install when missing, update (reinstall) an outdated app-owned binary, or
  /// nudge when an external binary is too old. Returns true if the server should
  /// start afterward (it should in every case except a failed install).
  @discardableResult
  func ensureReady() async -> Bool {
    let status = await Task.detached { LlamaBinaries.status() }.value
    switch status {
    case .ready(_, _, let version):
      currentVersion = version
      state = .idle
      return true

    case .missing:
      return await install()

    case .outdated(_, .appOwned, _):
      // The app owns this one -- update it to the latest.
      return await install()

    case .outdated(_, .external, let version):
      // Can't touch an external install; nudge but keep running (warn, not block).
      currentVersion = version
      state = .externalTooOld(version: version)
      return true
    }
  }

  /// Installs (or reinstalls) the app-owned binary, driving `state`. Also the
  /// retry entry point. Returns true on success.
  @discardableResult
  func install() async -> Bool {
    state = .installing
    do {
      try await LlamaInstaller.installLatest()
      logger.info("Installed the app-owned llama CLI")
      // Refresh before flipping to .idle so the rebuild triggered by the state
      // change already reflects the freshly-installed version.
      await refreshVersion()
      state = .idle
      return true
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      logger.error("CLI install failed: \(message, privacy: .public)")
      state = .failed(message: message)
      return false
    }
  }

  /// Reads the in-use binary's version off the main thread and caches it.
  private func refreshVersion() async {
    currentVersion = await Task.detached {
      guard let path = LlamaBinaries.llamaPath else { return nil }
      return LlamaBinaries.readVersion(at: path)
    }.value
  }
}
