import AppKit
import Foundation

/// Handles user actions on model items (start, stop, download, delete, etc.).
/// Decouples business logic from the view.
///
/// No menu refresh happens here: every `ModelManager` mutation below posts a
/// downloads/installed-list notification, and `MenuController` rebuilds on those.
@MainActor
final class ModelActionHandler {
  private let modelManager = ModelManager.shared
  private let server = LlamaServer.shared

  func performPrimaryAction(for model: Model) {
    if modelManager.isInstalled(model) {
      if server.isActive(model: model) {
        server.unloadModel(model)
      } else {
        server.loadModel(model)
      }
    } else if modelManager.isDownloading(model) {
      // Non-destructive: stop the transfer but keep the `.partial` bytes so the row
      // flips to paused and the user can resume with another click. Discard is the
      // explicit red-X action, not row-body / pause-button click.
      modelManager.pauseModelDownload(model)
    } else {
      // Available OR paused — downloadModel resumes from an existing `.partial` if present.
      startDownload(for: model)
    }
  }

  func delete(model: Model) {
    guard modelManager.isInstalled(model) else { return }
    modelManager.deleteDownloadedModel(model)
  }

  /// Discards an in-flight or paused download and its `.partial` files.
  /// Used by the red X button; works in both `.downloading` and `.paused` states.
  func cancelDownload(for model: Model) {
    modelManager.cancelModelDownload(model)
  }

  private func startDownload(for model: Model) {
    do {
      try modelManager.downloadModel(model)
    } catch {
      ModalPresentation.showAlert(
        style: .warning,
        title: error.localizedDescription,
        body: (error as? LocalizedError)?.recoverySuggestion)
    }
  }
}
