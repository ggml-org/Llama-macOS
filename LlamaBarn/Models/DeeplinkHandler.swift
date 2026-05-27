import AppKit
import Foundation
import os.log

/// Consumes `llamabarn://` URLs and turns them into `ModelManager` downloads.
///
/// Design notes:
///   - Silent start: the download just begins in the background. User clicks
///     the menu bar icon to see progress. No auto-popup — browser already
///     showed a "Open in LlamaBarn?" prompt, so no extra confirmation here
///     either.
///   - No cross-launch persistence: if the app dies mid-download, the
///     `.partial` bytes stay on disk. Re-clicking the same deeplink resolves
///     to the same URLs and `openPartialWriter` resumes from those bytes.
@MainActor
final class DeeplinkHandler {
  static let shared = DeeplinkHandler()

  private let logger = Logger(subsystem: Logging.subsystem, category: "DeeplinkHandler")

  func handle(url: URL) {
    guard let parsed = LlamabarnURL.parse(url) else {
      logger.info("Ignoring unrecognized URL: \(url.absoluteString, privacy: .public)")
      return
    }

    switch parsed {
    case .install(let repo, let quant):
      Task { await resolveAndInstall(repo: repo, quant: quant) }
    }
  }

  private func resolveAndInstall(repo: String, quant: String?) async {
    let manager = ModelManager.shared
    let token: String? = {
      let t = UserSettings.hfToken ?? ""
      return t.isEmpty ? nil : t
    }()

    let resolved: HFRepoResolver.Resolved
    do {
      resolved = try await HFRepoResolver.resolve(
        repo: repo,
        quant: quant,
        systemMemoryMb: SystemMemory.memoryMb,
        token: token
      )
    } catch {
      logger.error(
        "Deeplink resolve failed for \(repo, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      // `ResolveError` carries a user-facing title + recovery suggestion split;
      // anything else collapses to a generic title with the raw error as body.
      if let err = error as? HFRepoResolver.ResolveError {
        presentAlert(
          title: err.errorDescription ?? "Couldn’t install this model.",
          body: err.recoverySuggestion)
      } else {
        presentAlert(title: "Couldn’t install this model.", body: error.localizedDescription)
      }
      return
    }

    // Already installed? Surface a hint so repeating the deeplink doesn't feel like a no-op.
    if let existing = manager.downloadedModels.first(where: {
      $0.id == resolved.modelId || $0.downloadUrl == resolved.mainUrl
    }) {
      logger.info("Deeplink \(resolved.modelId, privacy: .public) is already installed")
      postHint("\(existing.displayName) is already installed")
      return
    }

    let entry = Model.placeholderForDownload(
      modelId: resolved.modelId,
      repo: resolved.repo,
      quant: resolved.quant,
      mainUrl: resolved.mainUrl,
      additionalParts: resolved.additionalParts,
      mmprojUrl: resolved.mmprojUrl,
      fileSize: resolved.approximateBytes)

    do {
      try manager.downloadModel(entry)
      // Acknowledge the deeplink with a speech bubble near the menu bar icon --
      // resolve can take a few seconds, so this is often the user's first sign
      // that the click landed. The bubble dismisses the moment they open the
      // menu, where progress is surfaced.
      postHint("Downloading \(entry.displayName)…")
    } catch {
      presentAlert(
        title: "Couldn’t start the download.",
        body: (error as? LocalizedError)?.recoverySuggestion ?? error.localizedDescription)
    }
  }

  private func postHint(_ message: String) {
    NotificationCenter.default.post(
      name: .LBShowMenuHint, object: nil, userInfo: ["message": message])
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
