import Foundation
import os.log

/// Observable owner of the app-managed CLI install. Holds the install `state` so
/// the menu can surface a "setting up…" banner and a retry affordance, and
/// drives `LlamaInstaller` off the UI.
///
/// The install itself is silent (no permission prompt): it writes only to
/// `~/.llama-app` / `~/.local/bin`, needs no privilege escalation, and is part
/// of the app's "it just works" setup -- but it's never opaque, hence the state.
@MainActor
final class LlamaInstallManager {
  static let shared = LlamaInstallManager()

  private let logger = Logger(subsystem: Logging.subsystem, category: "LlamaInstallManager")

  enum State: Equatable {
    /// Ready -- a usable binary is present (or we haven't needed to act).
    case idle
    /// Downloading/installing the app-managed binary.
    case installing
    /// The install failed; `message` is user-facing. Retry via `install()`.
    case failed(message: String)
    /// An unmanaged (e.g. Homebrew) binary is present but below `floorVersion`.
    /// The app can't update it, so it nudges the user to do so. Non-blocking:
    /// the server still runs, since the old binary often works.
    case unmanagedTooOld(version: LlamaVersion)
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

  /// Ensures a usable `llama` binary is available, applying the version policy:
  /// install when missing, reconcile the managed binary to the pinned target
  /// when it differs, or nudge when an unmanaged binary is below the floor.
  /// Returns true if the server should start afterward (always, except a failed
  /// install).
  @discardableResult
  func ensureReady() async -> Bool {
    switch await Task.detached(operation: { LlamaBinaries.installed() }).value {
    case .missing:
      return await install()

    case .present(.managed, let version):
      // The app manages this one -- keep it at the pinned target. A nil version
      // (unreadable) fails open as ready, to avoid a reinstall loop.
      if let version, version != LlamaBinaries.targetVersion {
        return await install()
      }
      currentVersion = version
      state = .idle
      return true

    case .present(.unmanaged, let version):
      // Can't touch an unmanaged install; nudge if below the floor but keep
      // running (warn, not block).
      currentVersion = version
      if let version, version < LlamaBinaries.floorVersion {
        state = .unmanagedTooOld(version: version)
      } else {
        state = .idle
      }
      return true
    }
  }

  /// Installs (or reinstalls) the app-managed binary at the pinned target,
  /// driving `state`. Also the retry entry point. Returns true on success.
  @discardableResult
  func install() async -> Bool {
    state = .installing
    do {
      try await LlamaInstaller.install(version: LlamaBinaries.targetVersion.tag)
      logger.info("Installed the app-managed llama CLI")
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
