import AppKit
import Foundation
import os.log

/// Consumes `llamabarn://` URLs and turns them into `ModelManager` state:
/// parses → resolves against HF → registers pending state when needed → starts
/// the download.
///
/// Errors surface as `NSAlert`; malformed URLs are swallowed (and logged).
/// The browser's "Open this link in LlamaBarn?" prompt is the consent
/// boundary — we don't add a second confirmation modal on top of it.
@MainActor
final class DeeplinkHandler {
  static let shared = DeeplinkHandler()

  private let logger = Logger(subsystem: Logging.subsystem, category: "DeeplinkHandler")

  /// Weak reference to the app's `MenuController` so a deeplink can reveal the
  /// menu when a download starts. Wired up from `AppDelegate` after the menu
  /// is built. Optional — a nil menuController is a soft failure: the download
  /// still starts, just without the menu-flash feedback.
  weak var menuController: MenuController?

  /// Why we're running the deeplink pipeline. Controls user-visible side
  /// effects (alerts on failure, menu-pop on success) — the resolve/download
  /// mechanics are identical across origins.
  private enum Origin {
    /// User clicked a `llamabarn://` link (browser handoff, manual `open`,
    /// HF "Use this model" dropdown). They're actively waiting for feedback,
    /// so show alerts on failure and pop the menu on success.
    case userClick

    /// App just launched with a pending deeplink persisted from an earlier
    /// session. The user didn't ask for anything right now — they'd be
    /// startled by a modal or a menu that pops open on its own.
    case rehydrate

    var showsAlerts: Bool {
      switch self {
      case .userClick: return true
      case .rehydrate: return false
      }
    }

    var revealsMenu: Bool {
      switch self {
      case .userClick: return true
      case .rehydrate: return false
      }
    }
  }

  func handle(url: URL) {
    guard let parsed = LlamabarnURL.parse(url) else {
      logger.info("Ignoring unrecognized URL: \(url.absoluteString, privacy: .public)")
      return
    }

    switch parsed {
    case .install(let repo, let quant):
      Task { await resolveAndInstall(repo: repo, quant: quant, origin: .userClick) }
    }
  }

  /// Re-resolves a persisted pending install and kicks off (or resumes) its
  /// download. Called from `ModelManager.hydratePendingInstalls` on app launch.
  func rehydrate(descriptor: PendingInstallDescriptor) {
    Task {
      await resolveAndInstall(
        repo: descriptor.repo, quant: descriptor.quant, origin: .rehydrate)
    }
  }

  private func resolveAndInstall(
    repo: String, quant: String?, origin: Origin
  ) async {
    let manager = ModelManager.shared
    let token: String? = {
      let t = UserSettings.hfToken ?? ""
      return t.isEmpty ? nil : t
    }()
    let catalog = Catalog.allModels() + manager.downloadedModels.filter(\.isSideloaded)

    let resolved: HFRepoResolver.Resolved
    do {
      resolved = try await HFRepoResolver.resolve(
        repo: repo,
        quant: quant,
        catalog: catalog,
        systemMemoryMb: SystemMemory.memoryMb,
        token: token
      )
    } catch let err as HFRepoResolver.ResolveError {
      logger.error(
        "Deeplink resolve failed for \(repo, privacy: .public): \(err.localizedDescription, privacy: .public)"
      )
      if origin.showsAlerts {
        presentAlert(
          title: err.errorDescription ?? "Couldn’t install this model.",
          body: err.recoverySuggestion)
      }
      return
    } catch {
      logger.error(
        "Deeplink resolve failed for \(repo, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      if origin.showsAlerts {
        presentAlert(title: "Couldn’t install this model.", body: error.localizedDescription)
      }
      return
    }

    // Already installed (either as a catalog entry with the same download URL,
    // or as a previously-sideloaded model with the matching id)? Reveal the
    // menu and stop — don't re-download. On rehydrate, also drop the stale
    // pending descriptor that survived relaunch.
    if manager.downloadedModels.contains(where: { $0.id == resolved.modelId })
      || manager.downloadedModels.contains(where: { $0.downloadUrl == resolved.mainUrl })
    {
      logger.info(
        "Deeplink \(resolved.modelId, privacy: .public) is already installed; revealing menu")
      manager.discardPendingInstall(id: resolved.modelId)
      if origin.revealsMenu { menuController?.openMenu() }
      return
    }

    // Catalog hit (non-deeplink flow already exists) — delegate to the standard
    // download path and skip the pending-install registry entirely.
    if let catalogEntry = Catalog.allModels().first(where: {
      $0.downloadUrl == resolved.mainUrl
    }) {
      // On rehydrate the catalog might have absorbed this repo between sessions.
      manager.discardPendingInstall(id: resolved.modelId)
      startDownload(catalogEntry, manager: manager, origin: origin)
      return
    }

    // Sideload path: synthesize a placeholder `CatalogEntry` whose id matches
    // what `scanForSideloaded` will emit post-download, register it as pending,
    // and kick off the transfer. `registerPendingInstall` replaces any existing
    // placeholder (from hydrate) with this fully-resolved entry.
    let entry = CatalogEntry.sideloadPlaceholder(
      modelId: resolved.modelId,
      repo: resolved.repo,
      quant: resolved.quant,
      mainUrl: resolved.mainUrl,
      additionalParts: resolved.additionalParts,
      mmprojUrl: resolved.mmprojUrl,
      fileSize: resolved.approximateBytes)
    let descriptor = PendingInstallDescriptor(
      modelId: resolved.modelId, repo: resolved.repo, quant: resolved.quant)
    manager.upsertPendingInstall(entry: entry, descriptor: descriptor)
    startDownload(entry, manager: manager, origin: origin)
  }

  private func startDownload(
    _ entry: CatalogEntry, manager: ModelManager, origin: Origin
  ) {
    do {
      try manager.downloadModel(entry)
      if origin.revealsMenu { menuController?.openMenu() }
    } catch {
      if origin.showsAlerts {
        presentAlert(
          title: "Couldn’t start the download.",
          body: (error as? LocalizedError)?.recoverySuggestion ?? error.localizedDescription)
      }
    }
  }

  private func presentAlert(title: String, body: String?) {
    // Ensure the app can foreground the alert even in accessory (menu-bar)
    // activation mode.
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    if let body { alert.informativeText = body }
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
