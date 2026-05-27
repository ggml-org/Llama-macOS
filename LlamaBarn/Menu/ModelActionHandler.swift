import AppKit
import Foundation

/// Handles user actions on model items (start, stop, download, delete, etc.).
/// Decouples business logic from the view.
@MainActor
final class ModelActionHandler {
  private let modelManager: ModelManager
  private let server: LlamaServer
  private let onMembershipChange: (Model) -> Void

  init(
    modelManager: ModelManager,
    server: LlamaServer,
    onMembershipChange: @escaping (Model) -> Void
  ) {
    self.modelManager = modelManager
    self.server = server
    self.onMembershipChange = onMembershipChange
  }

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
      onMembershipChange(model)
    } else {
      // Available OR paused — downloadModel resumes from an existing `.partial` if present.
      startDownload(for: model)
    }
  }

  func delete(model: Model) {
    guard modelManager.isInstalled(model) else { return }
    modelManager.deleteDownloadedModel(model)
    onMembershipChange(model)
  }

  /// Discards an in-flight or paused download and its `.partial` files.
  /// Used by the red X button; works in both `.downloading` and `.paused` states.
  func cancelDownload(for model: Model) {
    modelManager.cancelModelDownload(model)
    onMembershipChange(model)
  }

  private func startDownload(for model: Model) {
    do {
      try modelManager.downloadModel(model)
      onMembershipChange(model)
    } catch {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = error.localizedDescription
      if let error = error as? LocalizedError, let recoverySuggestion = error.recoverySuggestion {
        alert.informativeText = recoverySuggestion
      }
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }
}
