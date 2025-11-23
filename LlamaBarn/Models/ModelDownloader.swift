import AppKit
import Foundation
import os.log

/// Manages the low-level details of downloading model files using URLSession.
class ModelDownloader: NSObject, URLSessionDownloadDelegate {
  static let shared = ModelDownloader()

  // Track multi-file downloads per model id
  struct ActiveDownload {
    var progress: Progress
    var tasks: [Int: URLSessionDownloadTask]
    var completedFilesBytes: Int64 = 0

    mutating func addTask(_ task: URLSessionDownloadTask) {
      tasks[task.taskIdentifier] = task
      refreshProgress()
    }

    mutating func removeTask(with identifier: Int) {
      tasks.removeValue(forKey: identifier)
      refreshProgress()
    }

    mutating func markTaskFinished(_ task: URLSessionDownloadTask, fileSize: Int64) {
      tasks.removeValue(forKey: task.taskIdentifier)
      completedFilesBytes += fileSize
      refreshProgress()
    }

    mutating func refreshProgress() {
      // Calculate both active and expected bytes in a single pass.
      // Called on every didWriteData callback (even with throttling, this is still 10x/sec per download),
      // so avoiding redundant iterations over tasks.values is important for responsiveness.
      var activeBytes: Int64 = 0
      var expectedActiveBytes: Int64 = 0

      for task in tasks.values {
        let received = task.countOfBytesReceived
        activeBytes += received
        let expected = task.countOfBytesExpectedToReceive
        expectedActiveBytes += expected > 0 ? expected : received
      }

      let totalCompleted = completedFilesBytes + activeBytes
      let totalExpected = max(progress.totalUnitCount, completedFilesBytes + expectedActiveBytes)
      progress.totalUnitCount = max(totalExpected, 1)
      progress.completedUnitCount = totalCompleted
    }

    var isEmpty: Bool { tasks.isEmpty }
  }

  var activeDownloads: [String: ActiveDownload] = [:]

  // Store resume data for failed downloads to allow resuming later
  private var resumeData: [URL: Data] = [:]

  private var urlSession: URLSession!
  private let logger = Logger(subsystem: Logging.subsystem, category: "ModelDownloader")

  // Throttle progress notifications to prevent excessive UI refreshes.
  // URLSession's didWriteData can fire hundreds of times per second during fast downloads,
  // and each notification triggers a full menu refresh. Limiting to 10 updates/sec (100ms)
  // maintains smooth progress UI while avoiding performance bottlenecks.
  private var lastNotificationTime: [String: Date] = [:]
  private let notificationThrottleInterval: TimeInterval = 0.1

  private override init() {
    super.init()
    // URLSession delegate callbacks run on background queue to avoid blocking main thread during file operations.
    // State access is synchronized by dispatching to main queue when needed.
    let queue = OperationQueue()
    queue.qualityOfService = .userInitiated
    urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: queue)
  }

  func status(for model: CatalogEntry) -> ModelStatus {
    if let download = activeDownloads[model.id] {
      return .downloading(download.progress)
    }
    return .available
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

  /// Cancels an ongoing download and removes it from tracking
  func cancelModelDownload(_ model: CatalogEntry) {
    if activeDownloads[model.id] != nil {
      cancelTasks(for: model.id)
      activeDownloads.removeValue(forKey: model.id)
      lastNotificationTime.removeValue(forKey: model.id)
    }
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
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
    return files
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
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
        task: downloadTask,
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
      // Threshold is 1 MB minimum, or half the expected size if expected size < 20 MB.
      // This catches obviously broken downloads (network errors, server issues) while
      // allowing small models and avoiding false positives on large multi-GB files.
      let tenMB: Int64 = 10 * 1_000_000
      let minAcceptableBytes = min(model.fileSize / 2, tenMB)
      let minThreshold = max(Int64(1_000_000), minAcceptableBytes)
      if fileSize <= minThreshold {
        try? fileManager.removeItem(at: destinationURL)
        handleDownloadFailure(
          modelId: modelId,
          model: model,
          task: downloadTask,
          tempLocation: nil,
          destinationURL: destinationURL,
          reason: "file too small (\(fileSize) B)"
        )
        return
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
          NotificationCenter.default.post(
            name: .LBModelDownloadFinished,
            object: self,
            userInfo: ["model": model]
          )
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

  private func handleDownloadFailure(
    modelId: String,
    model: CatalogEntry,
    task: URLSessionDownloadTask,
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

    logger.error("Model download failed (\(reason)) for model: \(model.displayName)")

    // State access must happen on main queue
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.cancelActiveDownload(modelId: modelId)
      self.postDownloadsDidChange()
    }
  }

  func urlSession(
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

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let modelId = task.taskDescription else {
      return
    }

    if let error = error {
      // Ignore cancellation errors as they are expected when user cancels
      if (error as NSError).code == NSURLErrorCancelled {
        return
      }

      logger.error("Model download failed: \(error.localizedDescription)")

      let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
      let originalURL = task.originalRequest?.url

      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }

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
        }
      }
    }
  }

  // MARK: - Helpers

  private func cancelTasks(for modelId: String) {
    guard let download = activeDownloads[modelId] else { return }

    for task in download.tasks.values {
      task.cancel(byProducingResumeData: { [weak self] data in
        guard let self = self, let data = data, let url = task.originalRequest?.url else { return }
        DispatchQueue.main.async {
          self.resumeData[url] = data
          self.logger.info("Saved resume data for cancelled download: \(url.lastPathComponent)")
        }
      })
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

  private func validateCompatibility(for model: CatalogEntry) throws {
    guard Catalog.isModelCompatible(model) else {
      let reason =
        Catalog.incompatibilitySummary(model)
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
      let needStr = DiskSpace.formatGB(remainingBytes)
      let haveStr = DiskSpace.formatGB(available)
      throw DownloadError.notEnoughDiskSpace(required: needStr, available: haveStr)
    }
  }

  private func postDownloadsDidChange() {
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }
}
