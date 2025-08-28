import Combine
import Foundation
import Observation
import os.log

/// Represents the current status of a model
enum ModelStatus: Equatable {
  case available
  case downloading(Progress)
  case downloaded

  static func == (lhs: ModelStatus, rhs: ModelStatus) -> Bool {
    switch (lhs, rhs) {
    case (.available, .available), (.downloaded, .downloaded):
      return true
    case (.downloading(let lhsProgress), .downloading(let rhsProgress)):
      return lhsProgress === rhsProgress
    default:
      return false
    }
  }
}

/// Manages downloading and tracking of AI models from remote repositories
@Observable
class ModelManager: NSObject, URLSessionDownloadDelegate {
  static let shared = ModelManager()

  var downloadedModels: [ModelCatalogEntry] = []
  var activeDownloads: [String: (progress: Progress, task: URLSessionDownloadTask)] = [:]
  var modelsBeingDeleted: Set<String> = []
  var downloadUpdateTrigger: Int = 0

  private var urlSession: URLSession!
  private let logger = Logger(subsystem: "LlamaBarn", category: "ModelManager")

  private override init() {
    super.init()
    urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    refreshDownloadedModels()
  }

  /// Determines which files need downloading for the given model
  private func filesRequired(for model: ModelCatalogEntry) -> [URL] {
    var files: [URL] = []

    if !FileManager.default.fileExists(atPath: model.modelFilePath) {
      files.append(model.downloadUrl)
    }

    if let visionFile = model.visionFile,
      !FileManager.default.fileExists(atPath: model.visionFilePath!)
    {
      files.append(visionFile)
    }

    return files
  }

  /// Downloads all required files for a model
  func downloadModel(_ model: ModelCatalogEntry) {
    let filesToDownload = filesRequired(for: model)
    guard !filesToDownload.isEmpty else {
      return
    }

    logger.info("Starting download for model: \(model.displayName)")

    for fileUrl in filesToDownload {
      let task = urlSession.downloadTask(with: fileUrl)
      task.taskDescription = model.id
      activeDownloads[model.id] = (
        progress: Progress(totalUnitCount: Int64(model.fileSizeMB * 1_048_576)), task: task
      )
      task.resume()
    }
  }

  /// Gets the current status of a model
  func getModelStatus(_ model: ModelCatalogEntry) -> ModelStatus {
    if let download = activeDownloads[model.id] {
      return .downloading(download.progress)
    } else if modelsBeingDeleted.contains(model.id) || !model.isDownloaded {
      return .available
    } else {
      return .downloaded
    }
  }

  /// Checks if a model has been completely downloaded
  func isModelDownloaded(_ model: ModelCatalogEntry) -> Bool {
    return getModelStatus(model) == .downloaded
  }

  /// Safely deletes a downloaded model and its associated files
  /// Automatically stops the server if the model is currently active
  func deleteDownloadedModel(_ model: ModelCatalogEntry) {
    // Ensure server is stopped if this model is currently running
    let llamaServer = LlamaServer.shared
    if llamaServer.activeModelPath == model.modelFilePath {
      // Stop the active server before deleting its model
      llamaServer.stop()
    }

    // Mark model as being deleted for immediate UI feedback
    modelsBeingDeleted.insert(model.id)

    // Immediately remove from UI for responsive feedback
    downloadedModels.removeAll { $0.id == model.id }

    // Perform actual file deletion asynchronously
    Task {
      do {
        // Remove the main model file
        try FileManager.default.removeItem(atPath: model.modelFilePath)

        // Safely remove vision file only if no other models depend on it
        if let visionFilePath = model.visionFilePath, canDeleteVisionFile(model: model) {
          try FileManager.default.removeItem(atPath: visionFilePath)
        }

        // Successfully deleted - remove from being deleted set
        await MainActor.run {
          self.modelsBeingDeleted.remove(model.id)
        }
      } catch {
        // If deletion fails, add the model back to the list and remove from being deleted
        await MainActor.run {
          self.modelsBeingDeleted.remove(model.id)
          // Re-check if files still exist after failed deletion
          if model.isDownloaded {
            self.downloadedModels.append(model)
          }
        }
        logger.error("Failed to delete model: \(error.localizedDescription)")
      }
    }
  }

  /// Determines if a vision file can be safely deleted by checking reference count
  private func canDeleteVisionFile(model: ModelCatalogEntry) -> Bool {
    guard let visionFilePath = model.visionFilePath else { return false }

    // Count how many downloaded models use this vision file
    let referenceCount = downloadedModels.count { downloadedModel in
      downloadedModel.visionFilePath == visionFilePath
    }

    // Safe to delete if only this model uses it (reference count of 1)
    return referenceCount <= 1
  }

  /// Scans the local models directory and updates the list of downloaded models
  func refreshDownloadedModels() {
    downloadedModels = ModelCatalog.models.filter { $0.isDownloaded }
  }

  /// Cancels an ongoing download and removes it from tracking
  func cancelModelDownload(_ model: ModelCatalogEntry) {
    if let download = activeDownloads[model.id] {
      download.task.cancel()
      activeDownloads.removeValue(forKey: model.id)
    }
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let modelId = downloadTask.taskDescription,
      let model = ModelCatalog.models.first(where: { $0.id == modelId })
    else {
      return
    }

    let fileManager = FileManager.default
    let destinationURL = URL(fileURLWithPath: model.modelFilePath)

    do {
      if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
      }
      try fileManager.moveItem(at: location, to: destinationURL)

      DispatchQueue.main.async {
        self.logger.info("Download completed for model: \(model.displayName)")
        self.activeDownloads.removeValue(forKey: modelId)
        self.refreshDownloadedModels()
      }
    } catch {
      logger.error("Error moving downloaded file: \(error.localizedDescription)")
      DispatchQueue.main.async {
        self.activeDownloads.removeValue(forKey: modelId)
      }
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard let modelId = downloadTask.taskDescription,
      let download = activeDownloads[modelId]
    else {
      return
    }

    DispatchQueue.main.async {
      download.progress.completedUnitCount = totalBytesWritten
      self.downloadUpdateTrigger += 1
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let modelId = task.taskDescription else {
      return
    }

    if let error = error {
      logger.error("Model download failed: \(error.localizedDescription)")
      DispatchQueue.main.async {
        self.activeDownloads.removeValue(forKey: modelId)
      }
    }
  }
}
