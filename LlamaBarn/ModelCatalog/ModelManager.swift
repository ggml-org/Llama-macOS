import AppKit
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
  // Track multi-file downloads per model id
  struct ActiveDownload {
    var progress: Progress
    var tasks: [Int: URLSessionDownloadTask]  // key: taskIdentifier
    var bytesWritten: [Int: Int64]  // per-task completed bytes
    var expectedBytes: [Int: Int64]  // per-task expected bytes (if known)
    var totalExpectedBytes: Int64  // aggregate expected (dynamic)
  }
  var activeDownloads: [String: ActiveDownload] = [:]
  var modelsBeingDeleted: Set<String> = []
  var downloadUpdateTrigger: Int = 0

  private var urlSession: URLSession!
  private let logger = Logger(subsystem: "LlamaBarn", category: "ModelManager")

  private override init() {
    super.init()
    // Route delegate callbacks to the main queue to keep state access consistent
    urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    refreshDownloadedModels()
  }

  /// Determines which files need downloading for the given model
  private func filesRequired(for model: ModelCatalogEntry) -> [URL] {
    var files: [URL] = []

    // Main model file
    if !FileManager.default.fileExists(atPath: model.modelFilePath) {
      files.append(model.downloadUrl)
    }

    // Additional shards
    if let additional = model.additionalParts, !additional.isEmpty {
      let baseDir = URL(fileURLWithPath: model.modelFilePath).deletingLastPathComponent()
      for url in additional {
        let path = baseDir.appendingPathComponent(url.lastPathComponent).path
        if !FileManager.default.fileExists(atPath: path) {
          files.append(url)
        }
      }
    }

    // No separate vision file support.

    return files
  }

  /// Downloads all required files for a model
  func downloadModel(_ model: ModelCatalogEntry) {
    let filesToDownload = filesRequired(for: model)
    guard !filesToDownload.isEmpty else {
      return
    }

    // Before starting, ensure there's enough free disk space on the models volume.
    // Estimate remaining bytes needed as catalog total minus already-present files.
    let totalBytes = model.fileSize
    let existingBytes: Int64 = model.allLocalModelPaths.reduce(0) { sum, path in
      guard FileManager.default.fileExists(atPath: path),
        let attrs = try? FileManager.default.attributesOfItem(atPath: path),
        let size = (attrs[.size] as? NSNumber)?.int64Value
      else { return sum }
      return sum + size
    }
    let remainingBytes = max(totalBytes - existingBytes, 0)
    let modelsDir = URL(fileURLWithPath: model.modelFilePath).deletingLastPathComponent()
    let available = DiskSpace.availableBytes(at: modelsDir)

    if available > 0 && remainingBytes > available {
      // Not enough space — inform the user and do not start the download.
      let needStr = DiskSpace.formatGB(remainingBytes)
      let haveStr = DiskSpace.formatGB(available)
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Not enough disk space"
      alert.informativeText =
        "\(model.displayName) requires \(needStr) free in ~/.llamabarn, but only \(haveStr) is available. Free up space or choose a smaller model."
      alert.addButton(withTitle: "OK")
      alert.runModal()
      return
    }

    logger.info("Starting download for model: \(model.displayName)")

    // Create or reuse aggregate state for this model's downloads
    var aggregate =
      activeDownloads[model.id]
      ?? ActiveDownload(
        // Start at 0 and grow as we learn expected sizes from the server/filesystem.
        // Using a fixed catalog estimate can briefly make completed > total when some shards report unknown sizes.
        progress: Progress(totalUnitCount: 0),
        tasks: [:],
        bytesWritten: [:],
        expectedBytes: [:],
        totalExpectedBytes: 0
      )

    // Publish aggregate before starting tasks to avoid race with delegate callbacks
    activeDownloads[model.id] = aggregate

    for fileUrl in filesToDownload {
      let task = urlSession.downloadTask(with: fileUrl)
      task.taskDescription = model.id
      aggregate.tasks[task.taskIdentifier] = task
      aggregate.bytesWritten[task.taskIdentifier] = 0
      aggregate.expectedBytes[task.taskIdentifier] = 0
      activeDownloads[model.id] = aggregate
      task.resume()
    }
  }

  /// Gets the current status of a model
  func getModelStatus(_ model: ModelCatalogEntry) -> ModelStatus {
    // Prefer real filesystem truth first: if all required files exist, it's downloaded.
    if model.isDownloaded { return .downloaded }
    // If it's being deleted or not fully present, it's available unless actively downloading
    if let download = activeDownloads[model.id] { return .downloading(download.progress) }
    if modelsBeingDeleted.contains(model.id) || !model.isDownloaded { return .available }
    return .downloaded
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

    // Cancel any in-flight downloads to avoid re-creating files while deleting
    cancelModelDownload(model)

    // Mark model as being deleted for immediate UI feedback
    modelsBeingDeleted.insert(model.id)

    // Immediately remove from UI for responsive feedback
    downloadedModels.removeAll { $0.id == model.id }
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)

    // Perform actual file deletion asynchronously
    Task {
      do {
        // Remove the main model file and any additional shards
        for path in model.allLocalModelPaths {
          if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
          }
        }

        // No separate vision file to remove

        // Successfully deleted - remove from being deleted set
        _ = await MainActor.run {
          self.modelsBeingDeleted.remove(model.id)
        }
        NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
      } catch {
        // If deletion fails, add the model back to the list and remove from being deleted
        _ = await MainActor.run {
          self.modelsBeingDeleted.remove(model.id)
          // Re-check if files still exist after failed deletion
          if model.isDownloaded {
            self.downloadedModels.append(model)
          }
        }
        NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
        logger.error("Failed to delete model: \(error.localizedDescription)")
      }
    }
  }

  // Removed: vision file reference counting; no longer applicable.

  /// Scans the local models directory and updates the list of downloaded models
  func refreshDownloadedModels() {
    downloadedModels = ModelCatalog.allEntries().filter { $0.isDownloaded }
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
  }

  /// Cancels an ongoing download and removes it from tracking
  func cancelModelDownload(_ model: ModelCatalogEntry) {
    if let download = activeDownloads[model.id] {
      for (_, task) in download.tasks { task.cancel() }
      activeDownloads.removeValue(forKey: model.id)
    }
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }

  // MARK: - URLSessionDownloadDelegate

  private func recalcProgress(for modelId: String) {
    guard var aggregate = activeDownloads[modelId] else { return }
    let totalBytes = aggregate.bytesWritten.values.reduce(0, +)
    let expected = aggregate.expectedBytes.values.reduce(0, +)
    if expected > 0 {
      aggregate.totalExpectedBytes = expected
    }
    // Ensure total never falls below completed to avoid Progress inconsistencies.
    let safeTotal = max(aggregate.totalExpectedBytes, totalBytes)
    aggregate.progress.totalUnitCount = safeTotal
    aggregate.progress.completedUnitCount = totalBytes
    activeDownloads[modelId] = aggregate
    downloadUpdateTrigger += 1
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let modelId = downloadTask.taskDescription,
      let model = ModelCatalog.entry(forId: modelId)
    else {
      return
    }

    let fileManager = FileManager.default
    let baseDir = URL(fileURLWithPath: model.modelFilePath).deletingLastPathComponent()
    // Place each file by its original filename inside the models directory
    let filename =
      downloadTask.originalRequest?.url?.lastPathComponent
      ?? URL(fileURLWithPath: model.modelFilePath).lastPathComponent
    let destinationURL = baseDir.appendingPathComponent(filename)

    do {
      if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
      }
      try fileManager.moveItem(at: location, to: destinationURL)

      // Mark this task as finished and finalize its byte counts (delegate already on main)
      if var aggregate = self.activeDownloads[modelId] {
        aggregate.tasks.removeValue(forKey: downloadTask.taskIdentifier)
        // Determine actual file size and promote to expected if unknown
        let fileSize =
          (try? FileManager.default.attributesOfItem(
            atPath: destinationURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        aggregate.bytesWritten[downloadTask.taskIdentifier] = fileSize
        if (aggregate.expectedBytes[downloadTask.taskIdentifier] ?? 0) <= 0 {
          aggregate.expectedBytes[downloadTask.taskIdentifier] = fileSize
        }
        self.activeDownloads[modelId] = aggregate
        self.recalcProgress(for: modelId)

        // If this was the last pending task, clear and refresh
        if aggregate.tasks.isEmpty {
          self.logger.info("All downloads completed for model: \(model.displayName)")
          self.activeDownloads.removeValue(forKey: modelId)
          self.refreshDownloadedModels()
        }
      } else {
        self.refreshDownloadedModels()
      }
    } catch {
      logger.error("Error moving downloaded file: \(error.localizedDescription)")
      // Remove this task but keep others going (delegate already on main)
      if var aggregate = self.activeDownloads[modelId] {
        aggregate.tasks.removeValue(forKey: downloadTask.taskIdentifier)
        self.activeDownloads[modelId] = aggregate
        self.recalcProgress(for: modelId)
        if aggregate.tasks.isEmpty { self.activeDownloads.removeValue(forKey: modelId) }
      }
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    // Delegate callbacks are delivered on main; update shared state directly.
    guard let modelId = downloadTask.taskDescription,
      var download = self.activeDownloads[modelId]
    else {
      return
    }
    download.bytesWritten[downloadTask.taskIdentifier] = totalBytesWritten
    // Sum all bytes across tasks to update aggregate progress
    let total = download.bytesWritten.values.reduce(0, +)
    // Update expected when server reports a known total for this task
    if totalBytesExpectedToWrite > 0 {
      download.expectedBytes[downloadTask.taskIdentifier] = totalBytesExpectedToWrite
    }
    let expectedTotal = download.expectedBytes.values.reduce(0, +)
    if expectedTotal > 0 {
      download.totalExpectedBytes = expectedTotal
    }
    // Keep total >= completed at all times.
    let safeTotal = max(download.totalExpectedBytes, total)
    download.progress.totalUnitCount = safeTotal
    download.progress.completedUnitCount = total
    self.activeDownloads[modelId] = download
    self.downloadUpdateTrigger += 1
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let modelId = task.taskDescription else {
      return
    }

    if let error = error {
      logger.error("Model download failed: \(error.localizedDescription)")
      // Remove only this failed task and keep tracking others (already on main)
      if var aggregate = self.activeDownloads[modelId] {
        aggregate.tasks.removeValue(forKey: task.taskIdentifier)
        self.activeDownloads[modelId] = aggregate
        self.recalcProgress(for: modelId)
        if aggregate.tasks.isEmpty {
          self.activeDownloads.removeValue(forKey: modelId)
        }
      }
    }
  }
}
