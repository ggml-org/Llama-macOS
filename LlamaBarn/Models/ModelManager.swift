import Foundation
import os.log

/// Represents the current status of a model
enum ModelStatus: Equatable {
  case available
  case downloading(Progress)
  case installed
}

/// Manages the high-level state of available and downloaded models.
@MainActor
class ModelManager: NSObject, URLSessionDownloadDelegate {
  static let shared = ModelManager()

  var downloadedModels: [CatalogEntry] = []

  /// Returns a sorted list of all models that are either installed or currently downloading.
  /// This is the primary list shown in the "Installed" section of the menu.
  var managedModels: [CatalogEntry] {
    (downloadedModels + downloadingModels).sorted(by: CatalogEntry.displayOrder(_:_:))
  }

  var downloadingModels: [CatalogEntry] {
    activeDownloads.values.map { $0.model }
  }

  var activeDownloads: [String: ActiveDownload] = [:]

  // Store resume data for failed downloads to allow resuming later
  private var resumeData: [URL: Data] = [:]

  private var urlSession: URLSession!
  private let logger = Logger(subsystem: Logging.subsystem, category: "ModelManager")

  // Throttle progress notifications to prevent excessive UI refreshes.
  private var lastNotificationTime: [String: Date] = [:]
  private let notificationThrottleInterval: TimeInterval = 0.1

  override init() {
    super.init()

    // URLSession delegate callbacks run on background queue to avoid blocking main thread during file operations.
    // State access is synchronized by dispatching to main queue when needed.
    let queue = OperationQueue()
    queue.qualityOfService = .userInitiated

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 120  // Increase timeout to handle temporary stalls
    config.timeoutIntervalForResource = 60 * 60 * 24  // 24 hours

    urlSession = URLSession(configuration: config, delegate: self, delegateQueue: queue)

    refreshDownloadedModels()
  }

  /// Downloads all required files for a model
  func downloadModel(_ model: CatalogEntry) throws {
    // Prevent duplicate downloads if user clicks download multiple times or if called from multiple code paths.
    // Without this check, we'd start redundant URLSession tasks, waste bandwidth, and corrupt download state.
    if activeDownloads[model.id] != nil {
      logger.info("Download already in progress for model: \(model.displayName)")
      return
    }

    let filesToDownload = try prepareDownload(for: model)
    guard !filesToDownload.isEmpty else { return }

    logger.info("Starting download for model: \(model.displayName)")

    // Publish aggregate before starting tasks to avoid race with delegate callbacks
    let modelId = model.id
    let totalUnitCount = max(remainingBytesRequired(for: model), 1)
    var aggregate = ActiveDownload(
      model: model,
      progress: Progress(totalUnitCount: totalUnitCount),
      tasks: [:],
      completedFilesBytes: 0
    )

    for fileUrl in filesToDownload {
      let task: URLSessionDownloadTask
      if let data = resumeData[fileUrl] {
        logger.info("Resuming download for \(fileUrl.lastPathComponent)")
        task = urlSession.downloadTask(withResumeData: data)
      } else {
        task = urlSession.downloadTask(with: fileUrl)
      }
      task.taskDescription = modelId
      aggregate.addTask(task)
      task.resume()
    }

    activeDownloads[modelId] = aggregate

    postDownloadsDidChange()
  }

  /// Gets the current status of a model.
  func status(for model: CatalogEntry) -> ModelStatus {
    if downloadedModels.contains(where: { $0.id == model.id }) {
      return .installed
    }
    if let download = activeDownloads[model.id] {
      return .downloading(download.progress)
    }
    return .available
  }

  /// Safely deletes a downloaded model and its associated files.
  func deleteDownloadedModel(_ model: CatalogEntry) {
    let llamaServer = LlamaServer.shared
    if llamaServer.activeModelPath == model.modelFilePath {
      llamaServer.stop()
    }
    cancelModelDownload(model)

    let paths = model.allLocalModelPaths

    // Optimistically update state immediately for responsive UI
    downloadedModels.removeAll { $0.id == model.id }
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)

    // Move file deletion to background queue to avoid blocking main thread
    let logger = self.logger
    Task.detached {
      do {
        // Delete files
        for path in paths {
          if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
          }
        }
      } catch {
        // If deletion failed, restore the model in the list
        await MainActor.run {
          Self.restoreDeletedModel(model, logger: logger, error: error)
        }
      }
    }
  }

  private static func restoreDeletedModel(_ model: CatalogEntry, logger: Logger, error: Error) {
    let manager = ModelManager.shared
    manager.downloadedModels.append(model)
    manager.downloadedModels.sort(by: CatalogEntry.displayOrder(_:_:))
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: manager)
    logger.error("Failed to delete model: \(error.localizedDescription)")
  }

  /// Scans the local models directory and updates the list of downloaded models.
  func refreshDownloadedModels() {
    let modelsDir = CatalogEntry.modelStorageDirectory

    // Move directory reading to background queue to avoid blocking main thread
    Task.detached {
      let downloaded: [CatalogEntry]
      if let files = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path) {
        let fileSet = Set(files)
        downloaded = Catalog.allModels().filter { model in
          let mainFile = model.downloadUrl.lastPathComponent
          if !fileSet.contains(mainFile) { return false }

          if let additionalParts = model.additionalParts {
            for part in additionalParts {
              if !fileSet.contains(part.lastPathComponent) { return false }
            }
          }
          return true
        }
      } else {
        downloaded = []
      }

      await MainActor.run {
        Self.updateDownloadedModels(downloaded)
      }
    }
  }

  private static func updateDownloadedModels(_ models: [CatalogEntry]) {
    let manager = ModelManager.shared
    manager.downloadedModels = models.sorted(by: CatalogEntry.displayOrder(_:_:))
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: manager)
  }

  /// Cancels an ongoing download.
  func cancelModelDownload(_ model: CatalogEntry) {
    if activeDownloads[model.id] != nil {
      cancelTasks(for: model.id)
      activeDownloads.removeValue(forKey: model.id)
      lastNotificationTime.removeValue(forKey: model.id)
    }
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }

  // MARK: - Convenience Methods

  /// Returns true if the model is installed (fully downloaded).
  func isInstalled(_ model: CatalogEntry) -> Bool {
    status(for: model) == .installed
  }

  /// Returns true if the model is currently downloading.
  func isDownloading(_ model: CatalogEntry) -> Bool {
    if case .downloading = status(for: model) { return true }
    return false
  }

  /// Returns the download progress if the model is currently downloading, nil otherwise.
  func downloadProgress(for model: CatalogEntry) -> Progress? {
    if case .downloading(let progress) = status(for: model) { return progress }
    return nil
  }

  // MARK: - URLSessionDownloadDelegate

  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let modelId = downloadTask.taskDescription,
      let model = Catalog.findModel(id: modelId)
    else {
      return
    }

    if let httpResponse = downloadTask.response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      handleDownloadFailure(
        modelId: modelId,
        model: model,
        tempLocation: location,
        destinationURL: nil,
        reason: "HTTP \(httpResponse.statusCode)"
      )
      return
    }

    let fileManager = FileManager.default
    let baseDir = URL(fileURLWithPath: model.modelFilePath).deletingLastPathComponent()
    let filename =
      downloadTask.originalRequest?.url?.lastPathComponent
      ?? URL(fileURLWithPath: model.modelFilePath).lastPathComponent
    let destinationURL = baseDir.appendingPathComponent(filename)

    // This callback runs on a background queue, so we can do blocking file operations safely.
    // URLSession's temp file is deleted when this callback returns, so we must move it before returning.
    do {
      if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
      }
      try fileManager.moveItem(at: location, to: destinationURL)

      let fileSize =
        (try? FileManager.default.attributesOfItem(
          atPath: destinationURL.path)[.size] as? NSNumber)?.int64Value ?? 0
      // Sanity check downloaded file size to catch truncated/corrupted downloads.
      let isSingleFile = (model.additionalParts ?? []).isEmpty && model.mmprojUrl == nil

      if isSingleFile {
        // For single-file models, we expect the file size to match exactly.
        if fileSize != model.fileSize {
          try? fileManager.removeItem(at: destinationURL)
          handleDownloadFailure(
            modelId: modelId,
            model: model,
            tempLocation: nil,
            destinationURL: destinationURL,
            reason: "file size mismatch (expected \(model.fileSize), got \(fileSize))"
          )
          return
        }
      } else {
        // For multi-part models, we use a heuristic.
        // Threshold is 1 MB minimum.
        // This catches obviously broken downloads (network errors, server issues).
        let minThreshold = Int64(1_000_000)
        if fileSize <= minThreshold {
          try? fileManager.removeItem(at: destinationURL)
          handleDownloadFailure(
            modelId: modelId,
            model: model,
            tempLocation: nil,
            destinationURL: destinationURL,
            reason: "file too small (\(fileSize) B)"
          )
          return
        }
      }

      // Update state on main queue (activeDownloads dict must be accessed from main queue)
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }

        // Clear resume data on success
        if let originalURL = downloadTask.originalRequest?.url {
          self.resumeData.removeValue(forKey: originalURL)
        }

        let wasCompleted = self.updateActiveDownload(modelId: modelId) { aggregate in
          aggregate.markTaskFinished(downloadTask, fileSize: fileSize)
        }

        if wasCompleted {
          self.logger.info("All downloads completed for model: \(model.displayName)")
          self.refreshDownloadedModels()
        }
        self.postDownloadsDidChange()
      }
    } catch {
      logger.error("Error moving downloaded file: \(error.localizedDescription)")
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        _ = self.updateActiveDownload(modelId: modelId) { aggregate in
          aggregate.removeTask(with: downloadTask.taskIdentifier)
        }
        self.postDownloadsDidChange()
      }
    }
  }

  nonisolated private func handleDownloadFailure(
    modelId: String,
    model: CatalogEntry,
    tempLocation: URL?,
    destinationURL: URL?,
    reason: String
  ) {
    let fileManager = FileManager.default
    if let tempLocation {
      try? fileManager.removeItem(at: tempLocation)
    }
    if let destinationURL, fileManager.fileExists(atPath: destinationURL.path) {
      try? fileManager.removeItem(at: destinationURL)
    }

    // State access must happen on main queue
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.logger.error("Model download failed (\(reason)) for model: \(model.displayName)")
      self.cancelActiveDownload(modelId: modelId)
      self.postDownloadsDidChange()
      NotificationCenter.default.post(
        name: .LBModelDownloadDidFail,
        object: self,
        userInfo: ["model": model, "error": reason]
      )
    }
  }

  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard let modelId = downloadTask.taskDescription else { return }

    // Access state on main queue
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard var download = self.activeDownloads[modelId] else {
        return
      }
      download.refreshProgress()
      self.activeDownloads[modelId] = download

      // Throttle notifications to avoid excessive UI updates
      let now = Date()
      let lastTime = self.lastNotificationTime[modelId] ?? .distantPast
      if now.timeIntervalSince(lastTime) >= self.notificationThrottleInterval {
        self.lastNotificationTime[modelId] = now
        self.postDownloadsDidChange()
      }
    }
  }

  nonisolated func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    guard let modelId = task.taskDescription else {
      return
    }

    if let error = error {
      // Ignore cancellation errors as they are expected when user cancels
      if (error as NSError).code == NSURLErrorCancelled {
        return
      }

      let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
      let originalURL = task.originalRequest?.url

      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.logger.error("Model download failed: \(error.localizedDescription)")

        // Save resume data if available
        if let originalURL {
          if let resumeData {
            self.resumeData[originalURL] = resumeData
            self.logger.info("Saved resume data for \(originalURL.lastPathComponent)")
          } else if self.resumeData[originalURL] != nil {
            self.logger.warning(
              "Download failed without resume data, clearing existing resume data for \(originalURL.lastPathComponent)"
            )
            self.resumeData.removeValue(forKey: originalURL)
          }
        }

        if self.activeDownloads[modelId] != nil {
          _ = self.updateActiveDownload(modelId: modelId) { aggregate in
            aggregate.removeTask(with: task.taskIdentifier)
          }
          self.postDownloadsDidChange()

          if let model = Catalog.findModel(id: modelId) {
            NotificationCenter.default.post(
              name: .LBModelDownloadDidFail,
              object: self,
              userInfo: ["model": model, "error": error.localizedDescription]
            )
          }
        }
      }
    }
  }

  // MARK: - Helpers

  private func cancelTasks(for modelId: String) {
    guard let download = activeDownloads[modelId] else { return }

    for task in download.tasks.values {
      // Cancel immediately without producing resume data.
      // This triggers the system to delete the temporary file, freeing up disk space.
      task.cancel()
    }
  }

  /// Updates an active download by applying a modification and removing it if empty.
  /// Returns true if the download was removed (completed or cancelled), false if still in progress.
  private func updateActiveDownload(
    modelId: String,
    modify: (inout ActiveDownload) -> Void
  ) -> Bool {
    guard var aggregate = activeDownloads[modelId] else { return false }

    modify(&aggregate)

    if aggregate.isEmpty {
      activeDownloads.removeValue(forKey: modelId)
      lastNotificationTime.removeValue(forKey: modelId)
      return true
    } else {
      activeDownloads[modelId] = aggregate
      return false
    }
  }

  /// Cancels all tasks for a model and removes it from active downloads.
  private func cancelActiveDownload(modelId: String) {
    if activeDownloads[modelId] != nil {
      cancelTasks(for: modelId)
      activeDownloads.removeValue(forKey: modelId)
      lastNotificationTime.removeValue(forKey: modelId)
    }
  }

  private func prepareDownload(for model: CatalogEntry) throws -> [URL] {
    let filesToDownload = filesRequired(for: model)
    guard !filesToDownload.isEmpty else { return [] }

    try validateCompatibility(for: model)

    let remainingBytes = remainingBytesRequired(for: model)
    try validateDiskSpace(for: model, remainingBytes: remainingBytes)

    return filesToDownload
  }

  /// Determines which files need downloading for the given model
  private func filesRequired(for model: CatalogEntry) -> [URL] {
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

    // Multimodal projection file
    if let mmprojUrl = model.mmprojUrl {
      let baseDir = URL(fileURLWithPath: model.modelFilePath).deletingLastPathComponent()
      let path = baseDir.appendingPathComponent(mmprojUrl.lastPathComponent).path
      if !FileManager.default.fileExists(atPath: path) {
        files.append(mmprojUrl)
      }
    }

    return files
  }

  private func validateCompatibility(for model: CatalogEntry) throws {
    guard model.isCompatible() else {
      let reason =
        model.incompatibilitySummary()
        ?? "isn't compatible with this Mac's memory."
      throw DownloadError.notCompatible(reason: reason)
    }
  }

  private func remainingBytesRequired(for model: CatalogEntry) -> Int64 {
    let existingBytes: Int64 = model.allLocalModelPaths.reduce(0) { sum, path in
      guard FileManager.default.fileExists(atPath: path),
        let attrs = try? FileManager.default.attributesOfItem(atPath: path),
        let size = (attrs[.size] as? NSNumber)?.int64Value
      else { return sum }
      return sum + size
    }
    return max(model.fileSize - existingBytes, 0)
  }

  private func validateDiskSpace(for model: CatalogEntry, remainingBytes: Int64) throws {
    guard remainingBytes > 0 else { return }

    let modelsDir = URL(fileURLWithPath: model.modelFilePath).deletingLastPathComponent()
    let available = DiskSpace.availableBytes(at: modelsDir)

    if available > 0 && remainingBytes > available {
      let needStr = Format.gigabytes(remainingBytes)
      let haveStr = Format.gigabytes(available)
      throw DownloadError.notEnoughDiskSpace(required: needStr, available: haveStr)
    }
  }

  private func postDownloadsDidChange() {
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }
}
