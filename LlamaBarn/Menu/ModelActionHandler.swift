import AppKit
import Foundation

/// Handles user actions on model items (start, stop, download, delete, etc.).
/// Decouples business logic from the view.
@MainActor
final class ModelActionHandler {
  private let modelManager: ModelManager
  private let server: LlamaServer
  private let onMembershipChange: (CatalogEntry) -> Void

  init(
    modelManager: ModelManager,
    server: LlamaServer,
    onMembershipChange: @escaping (CatalogEntry) -> Void
  ) {
    self.modelManager = modelManager
    self.server = server
    self.onMembershipChange = onMembershipChange
  }

  func performPrimaryAction(for model: CatalogEntry) {
    if modelManager.isInstalled(model) {
      if server.isActive(model: model) {
        server.unloadModel(model)
      } else {
        server.loadModel(model)
      }
    } else if modelManager.isDownloading(model) {
      modelManager.cancelModelDownload(model)
      onMembershipChange(model)
    } else {
      // Available -> Download
      startDownload(for: model)
    }
  }

  func delete(model: CatalogEntry) {
    guard modelManager.isInstalled(model) else { return }
    modelManager.deleteDownloadedModel(model)
    onMembershipChange(model)
  }

  func showInFinder(model: CatalogEntry) {
    guard modelManager.isInstalled(model) else { return }
    let url = URL(fileURLWithPath: model.modelFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func openHuggingFacePage(model: CatalogEntry) {
    NSWorkspace.shared.open(model.huggingFaceUrl)
  }

  func copyModelId(model: CatalogEntry) {
    copyText(model.id)
  }

  func copyText(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  private func startDownload(for model: CatalogEntry) {
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
