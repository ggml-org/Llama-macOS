import Foundation
import Sentry
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

  /// Resolved file paths for each downloaded model, keyed by model ID.
  /// Populated during refreshDownloadedModels(). Used for models.ini generation,
  /// deletion, and determining which files need downloading.
  var resolvedPaths: [String: ResolvedPaths] = [:]

  /// Returns a sorted list of all models that are either installed or currently downloading.
  /// This is the primary list shown in the "Installed" section of the menu.
  var managedModels: [CatalogEntry] {
    (downloadedModels + downloadingModels).sorted(by: CatalogEntry.displayOrder(_:_:))
  }

  var downloadingModels: [CatalogEntry] {
    activeDownloads.values.map { $0.model }
  }

  var activeDownloads: [String: ActiveDownload] = [:]

  /// HF download context per model ID, gathered before download starts.
  /// Contains commit hash and blob hashes needed to write into HF cache layout.
  /// Nil for legacy flat-directory downloads (fallback when HF API calls fail).
  var downloadContexts: [String: HFDownloadCtx] = [:]

  // Store resume data for failed downloads to allow resuming later
  private var resumeData: [URL: Data] = [:]

  // Retry state: tracks attempt count per URL for exponential backoff
  private var retryAttempts: [URL: Int] = [:]
  private let maxRetryAttempts = 3
  private let baseRetryDelay: TimeInterval = 2.0  // Doubles each attempt: 2s, 4s, 8s

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

  /// Downloads all required files for a model.
  /// Fetches HF metadata (commit hash, blob hashes) first, then starts URLSession tasks.
  /// Falls back to legacy flat download if HF API calls fail.
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

    // Add placeholder entry immediately so the model appears as "downloading"
    // in the UI before the async HF metadata fetch completes.
    let modelId = model.id
    let totalUnitCount = max(remainingBytesRequired(for: model), 1)
    activeDownloads[modelId] = ActiveDownload(
      model: model,
      progress: Progress(totalUnitCount: totalUnitCount),
      tasks: [:],
      completedFilesBytes: 0
    )
    postDownloadsDidChange()

    // Fetch HF metadata before starting download tasks.
    // This determines where files will be stored (HF cache vs legacy flat).
    Task {
      let ctx = await self.fetchHFContext(for: model)
      await MainActor.run {
        if let ctx {
          self.downloadContexts[modelId] = ctx
          self.logger.info("HF context ready for \(model.displayName): \(ctx.repoDir)")
        } else {
          self.logger.info("No HF context for \(model.displayName), using legacy download")
        }
        self.startDownloadTasks(model: model, files: filesToDownload)
      }
    }
  }

  /// Starts URLSession download tasks for the given files.
  private func startDownloadTasks(model: CatalogEntry, files: [URL]) {
    let modelId = model.id
    let totalUnitCount = max(remainingBytesRequired(for: model), 1)
    var aggregate = ActiveDownload(
      model: model,
      progress: Progress(totalUnitCount: totalUnitCount),
      tasks: [:],
      completedFilesBytes: 0
    )

    for fileUrl in files {
      let task: URLSessionDownloadTask
      if let data = resumeData[fileUrl] {
        logger.info("Resuming download for \(fileUrl.lastPathComponent)")
        task = urlSession.downloadTask(withResumeData: data)
      } else {
        task = urlSession.downloadTask(with: makeRequest(for: fileUrl))
      }
      task.taskDescription = modelId
      aggregate.addTask(task)
      task.resume()
    }

    activeDownloads[modelId] = aggregate

    postDownloadsDidChange()
  }

  /// Fetches HF file metadata (commit hash, blob hashes) for a model via HEAD requests.
  /// Each HEAD request returns both X-Repo-Commit and X-Linked-Etag, so one request
  /// per file gives us everything we need. Returns nil on failure (caller falls back to legacy).
  private nonisolated func fetchHFContext(for model: CatalogEntry) async -> HFDownloadCtx? {
    guard let repoDir = HFCache.repoDirName(from: model.downloadUrl) else { return nil }

    let token = await MainActor.run { UserSettings.hfToken }

    let allMetadata = await HFCache.fetchFileMetadata(
      for: model.allDownloadUrls, token: token)
    guard !allMetadata.isEmpty else { return nil }

    // All files in a repo share the same commit hash — take the first one we get
    let commit = allMetadata.values.compactMap(\.commitHash).first
    guard let commit else { return nil }

    // Collect blob hashes (some may be nil if header was missing)
    var blobHashes: [URL: String] = [:]
    for (url, metadata) in allMetadata {
      if let hash = metadata.blobHash {
        blobHashes[url] = hash
      }
    }

    return HFDownloadCtx(repoDir: repoDir, commit: commit, blobHashes: blobHashes)
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
    cancelModelDownload(model)

    // Clear active model if we're deleting the active model
    let llamaServer = LlamaServer.shared
    if llamaServer.activeModelId == model.id {
      llamaServer.activeModelId = nil
    }

    let paths = resolvedPaths[model.id]

    // Optimistically update state immediately for responsive UI
    downloadedModels.removeAll { $0.id == model.id }
    resolvedPaths.removeValue(forKey: model.id)
    if updateModelsFile() {
      LlamaServer.shared.reload()
    }
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)

    // Move file deletion to background queue to avoid blocking main thread
    let logger = self.logger
    Task.detached {
      do {
        if let paths {
          if paths.isLegacy {
            // Legacy: delete files directly
            for path in paths.allPaths {
              if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
              }
            }
          } else if let repoDir = paths.hfRepoDirName ?? model.hfRepoDir {
            // HF cache: delete blobs via symlinks, clean up empty dirs.
            // For sideloaded models, hfRepoDirName is stored in ResolvedPaths
            // since they don't have a download URL to derive it from.
            try HFCache.deleteModelFiles(
              cacheDir: UserSettings.hfCacheDirectory,
              repoDir: repoDir,
              paths: paths
            )
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
    // Re-scan to rebuild resolvedPaths
    manager.refreshDownloadedModels()
    logger.error("Failed to delete model: \(error.localizedDescription)")
  }

  /// Updates the `models.ini` file required for using llama-server in Router Mode.
  /// Returns true if the file was changed, false if content was identical.
  @discardableResult
  func updateModelsFile() -> Bool {
    let content = generateModelsFileContent()
    let destinationURL = CatalogEntry.legacyStorageDir.appendingPathComponent("models.ini")

    // Skip write if content is identical
    if let existingData = try? Data(contentsOf: destinationURL),
      let existingContent = String(data: existingData, encoding: .utf8),
      existingContent == content
    {
      return false
    }

    do {
      try content.write(to: destinationURL, atomically: true, encoding: .utf8)
      logger.info("Updated models.ini at \(destinationURL.path)")
      return true
    } catch {
      logger.error("Failed to write models.ini: \(error)")
      return false
    }
  }

  private func generateModelsFileContent() -> String {
    var content = ""

    for model in downloadedModels {
      // Use the effective tier (user selection or max compatible)
      guard let tier = model.effectiveCtxTier else { continue }

      let paths = resolvedPaths[model.id]

      // For HF cache models: use absolute snapshot path (symlink with human-readable filename).
      // For legacy models: use relative filename (llama-server CWD is ~/.llamabarn/).
      let modelPath: String
      let mmprojPath: String?
      if let paths, !paths.isLegacy {
        modelPath = paths.modelFile
        mmprojPath = paths.mmprojFile
      } else {
        modelPath = model.downloadUrl.lastPathComponent
        mmprojPath = model.mmprojUrl.map { model.localFilename(for: $0) }
      }

      content += "[\(model.id)]\n"
      content += "model = \(modelPath)\n"
      content += "ctx-size = \(tier.rawValue)\n"

      if let mmprojPath {
        content += "mmproj = \(mmprojPath)\n"
      }

      // Enable larger batch size for better performance on high-memory devices (>=32 GB RAM)
      let systemMemoryGb = Double(SystemMemory.memoryMb) / 1024.0
      if systemMemoryGb >= 32.0 {
        content += "ubatch-size = 2048\n"
      }

      // Add model-specific server arguments (sampling params, etc.)
      // We process only long arguments (e.g. "--temp" -> "0.7") to simplify parsing.
      // Short arguments are disallowed in the catalog to ensure consistent INI generation.
      var i = 0
      while i < model.serverArgs.count {
        let arg = model.serverArgs[i]

        // We only process arguments starting with "--"
        guard arg.hasPrefix("--") else {
          i += 1
          continue
        }

        let key = String(arg.dropFirst(2))

        if i + 1 < model.serverArgs.count && !model.serverArgs[i + 1].hasPrefix("-") {
          // Key-value pair (e.g. --temp 0.7)
          content += "\(key) = \(model.serverArgs[i + 1])\n"
          i += 2
        } else {
          // Boolean flag (e.g. --no-mmap)
          content += "\(key) = true\n"
          i += 1
        }
      }

      content += "\n"
    }
    return content
  }

  /// Active fit-params enrichment task. Cancelled on refresh to avoid stale updates.
  private var fitParamsTask: Task<Void, Never>?

  /// Scans both the legacy directory and HF cache for installed models,
  /// including sideloaded models that don't match any catalog entry.
  func refreshDownloadedModels() {
    let legacyDir = CatalogEntry.legacyStorageDir
    let hfCacheDir = UserSettings.hfCacheDirectory
    let allCatalogModels = Catalog.allModels()

    // Move directory reading to background queue to avoid blocking main thread
    Task.detached {
      var allResolved: [String: ResolvedPaths] = [:]

      // 1. Scan legacy directory (~/.llamabarn/) for flat .gguf files
      if let files = try? FileManager.default.contentsOfDirectory(atPath: legacyDir.path) {
        let fileSet = Set(files)
        for model in allCatalogModels {
          let mainFile = model.downloadUrl.lastPathComponent
          guard fileSet.contains(mainFile) else { continue }

          // Check additional parts (shards)
          var partsFound = true
          var partPaths: [String] = []
          if let additionalParts = model.additionalParts {
            for part in additionalParts {
              if fileSet.contains(part.lastPathComponent) {
                partPaths.append(legacyDir.appendingPathComponent(part.lastPathComponent).path)
              } else {
                partsFound = false
                break
              }
            }
          }
          guard partsFound else { continue }

          // Check mmproj file (uses localFilename override for legacy flat dir)
          var mmprojPath: String?
          if let mmprojUrl = model.mmprojUrl {
            let mmprojFile = model.localFilename(for: mmprojUrl)
            if fileSet.contains(mmprojFile) {
              mmprojPath = legacyDir.appendingPathComponent(mmprojFile).path
            } else {
              continue
            }
          }

          allResolved[model.id] = ResolvedPaths(
            modelFile: legacyDir.appendingPathComponent(mainFile).path,
            additionalParts: partPaths,
            mmprojFile: mmprojPath,
            isLegacy: true
          )
        }
      }

      // 2. Scan HF cache directory — overwrites legacy entries (HF cache is canonical)
      let hfScan = HFCache.scanForModels(cacheDir: hfCacheDir, catalog: allCatalogModels)
      for (modelId, paths) in hfScan.resolved {
        allResolved[modelId] = paths
      }

      // 3. Discover sideloaded models (GGUFs not matching any catalog entry)
      let sideloaded = HFCache.scanForSideloaded(
        cacheDir: hfCacheDir, knownFiles: hfScan.matchedFiles
      )

      // Apply cached fit-params to sideloaded models, track those still pending
      var sideloadedEntries: [CatalogEntry] = []
      var needsFitParams: [(id: String, path: String)] = []
      for (entry, paths) in sideloaded {
        var entry = entry
        if let cached = FitParamsCache.get(modelId: entry.id) {
          entry.ctxBytesPer1kTokens = cached.ctxBytesPer1kTokens
        } else {
          needsFitParams.append((id: entry.id, path: paths.modelFile))
        }
        allResolved[entry.id] = paths
        sideloadedEntries.append(entry)
      }

      // 4. Build downloaded models list from resolved paths
      let finalResolved = allResolved
      let catalogDownloaded = allCatalogModels.filter { finalResolved[$0.id] != nil }
      let allDownloaded = catalogDownloaded + sideloadedEntries

      let pendingFitParams = needsFitParams
      await MainActor.run {
        Self.updateDownloadedModels(
          allDownloaded, resolved: finalResolved, pending: pendingFitParams)
      }
    }
  }

  private static func updateDownloadedModels(
    _ models: [CatalogEntry],
    resolved: [String: ResolvedPaths],
    pending: [(id: String, path: String)] = []
  ) {
    let manager = ModelManager.shared
    manager.downloadedModels = models.sorted(by: CatalogEntry.displayOrder(_:_:))
    manager.resolvedPaths = resolved

    // Only reload server if models.ini actually changed
    if manager.updateModelsFile() {
      LlamaServer.shared.reload()
    }

    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: manager)

    // Kick off async fit-params computation for sideloaded models without cached results
    if !pending.isEmpty {
      manager.enrichSideloadedModels(pending)
    }
  }

  /// Runs llama-fit-params for sideloaded models that don't have cached results.
  /// Updates each model's ctxBytesPer1kTokens as results come in, refreshing the UI.
  /// Runs sequentially (one model at a time) to avoid GPU contention.
  private func enrichSideloadedModels(_ models: [(id: String, path: String)]) {
    // Cancel any previous enrichment task (e.g. from a previous refresh).
    // The withTaskCancellationHandler in FitParamsRunner.run() ensures the
    // subprocess is terminated when the task is cancelled.
    fitParamsTask?.cancel()

    fitParamsTask = Task.detached { [weak self] in
      for (modelId, modelPath) in models {
        guard !Task.isCancelled else { return }

        let params = await FitParamsRunner.run(modelPath: modelPath)
        guard !Task.isCancelled else { return }

        // On failure, cache a sentinel (-1) so the UI stops showing "estimating..."
        // and we don't re-run on next launch. The model falls back to 4k context.
        let resolved = params ?? FitParams(ctxBytesPer1kTokens: -1)

        // Cache the result to disk
        FitParamsCache.set(resolved, for: modelId)

        // Update the in-memory model entry and refresh the UI
        guard let mgr = self else { return }
        await MainActor.run {
          if let idx = mgr.downloadedModels.firstIndex(where: { $0.id == modelId }) {
            mgr.downloadedModels[idx].ctxBytesPer1kTokens = resolved.ctxBytesPer1kTokens
          }

          // Regenerate models.ini now that we have accurate memory info
          if mgr.updateModelsFile() {
            LlamaServer.shared.reload()
          }

          NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: mgr)
        }
      }
    }
  }

  /// Cancels an ongoing download.
  func cancelModelDownload(_ model: CatalogEntry) {
    if activeDownloads[model.id] != nil {
      cancelTasks(for: model.id)
      activeDownloads.removeValue(forKey: model.id)
      lastNotificationTime.removeValue(forKey: model.id)
      downloadContexts.removeValue(forKey: model.id)

      // Clear retry state for all URLs associated with this model
      for url in model.allDownloadUrls {
        clearRetryState(for: url)
        resumeData.removeValue(forKey: url)
      }
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
      // Map HTTP status codes to user-facing guidance. We deliberately don't claim a
      // specific cause (rate limit vs. gated repo vs. CDN outage) — Hugging Face uses
      // these codes for several reasons, so we hedge with "usually" and point the user
      // at the most common remedy.
      let userMessage: String
      switch httpResponse.statusCode {
      case 401:
        userMessage =
          "Hugging Face requires authentication for this download. Set a Hugging Face token in Settings and try again."
      case 403, 429:
        userMessage =
          "Hugging Face refused the download (HTTP \(httpResponse.statusCode)). This usually means a rate limit — try again in a few minutes, or set a Hugging Face token in Settings to lift the limit."
      case 404:
        userMessage =
          "Hugging Face returned 404 for this file. The catalog URL may be out of date — please report this at https://github.com/ggml-org/LlamaBarn/issues."
      case 500...599:
        userMessage =
          "Hugging Face is temporarily unavailable (HTTP \(httpResponse.statusCode)). Try again in a few minutes."
      default:
        userMessage = "Download failed with HTTP \(httpResponse.statusCode)."
      }

      // Keep the Sentry NSError description as the short technical string so existing
      // issue grouping (LlamaBarn.ModelManager: Code: NNN) stays intact across releases.
      let error = NSError(
        domain: "LlamaBarn.ModelManager",
        code: httpResponse.statusCode,
        userInfo: [
          NSLocalizedDescriptionKey: "Download failed with HTTP \(httpResponse.statusCode)",
          "modelId": modelId,
          "url": downloadTask.originalRequest?.url?.absoluteString ?? "unknown",
        ]
      )
      SentrySDK.capture(error: error)

      handleDownloadFailure(
        modelId: modelId,
        model: model,
        tempLocation: location,
        destinationURL: nil,
        reason: userMessage
      )
      return
    }

    let fileManager = FileManager.default
    let remoteUrl = downloadTask.originalRequest?.url
    let filename: String
    if let remoteUrl = remoteUrl {
      // For HF cache, always use the original remote filename (no localFilename override)
      // For legacy, use localFilename which handles mmprojLocalFilename overrides
      let ctx = DispatchQueue.main.sync { self.downloadContexts[modelId] }
      if ctx != nil {
        filename = remoteUrl.lastPathComponent
      } else {
        filename = model.localFilename(for: remoteUrl)
      }
    } else {
      filename = model.downloadUrl.lastPathComponent
    }

    // This callback runs on a background queue, so we can do blocking file operations safely.
    // URLSession's temp file is deleted when this callback returns, so we must move it before returning.
    do {
      // Check file size first (sanity check before moving)
      let fileSize =
        (try? FileManager.default.attributesOfItem(
          atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0

      // Sanity check: reject obviously broken downloads (error pages, empty files).
      // We don't check for exact size match because:
      // 1. URLSession already validates Content-Length (catches truncation)
      // 2. Catalog sizes can become stale if files are re-uploaded to HF
      // The 1 MB threshold catches garbage responses without being brittle.
      let minThreshold = Int64(1_000_000)
      if fileSize <= minThreshold {
        handleDownloadFailure(
          modelId: modelId,
          model: model,
          tempLocation: location,
          destinationURL: nil,
          reason: "file too small (\(fileSize) B)"
        )
        return
      }

      // Determine destination based on whether we have HF context
      let ctx = DispatchQueue.main.sync { self.downloadContexts[modelId] }

      if let ctx {
        // HF cache layout: write blob + snapshot symlink
        let cacheDir = DispatchQueue.main.sync { UserSettings.hfCacheDirectory }

        // Get pre-fetched blob hash, or compute SHA256 as fallback
        let blobHash: String
        if let hash = ctx.blobHashes[remoteUrl ?? model.downloadUrl] {
          blobHash = hash
        } else {
          blobHash = try HFCache.computeSHA256(of: location)
        }

        try HFCache.writeBlobAndLink(
          cacheDir: cacheDir,
          repoDir: ctx.repoDir,
          commit: ctx.commit,
          blobHash: blobHash,
          filename: filename,
          from: location
        )
      } else {
        // Legacy flat download: move to ~/.llamabarn/{filename}
        let baseDir = URL(fileURLWithPath: model.legacyModelFilePath).deletingLastPathComponent()
        let destinationURL = baseDir.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: destinationURL.path) {
          try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: location, to: destinationURL)
      }

      // Update state on main queue (activeDownloads dict must be accessed from main queue)
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }

        // Clear resume and retry data on success
        if let originalURL = downloadTask.originalRequest?.url {
          self.resumeData.removeValue(forKey: originalURL)
          self.clearRetryState(for: originalURL)
        }

        let wasCompleted = self.updateActiveDownload(modelId: modelId) { aggregate in
          aggregate.markTaskFinished(downloadTask, fileSize: fileSize)
        }

        if wasCompleted {
          self.logger.info("All downloads completed for model: \(model.displayName)")
          self.downloadContexts.removeValue(forKey: modelId)
          self.refreshDownloadedModels()
        }
        self.postDownloadsDidChange()
      }
    } catch {
      logger.error("Error handling downloaded file: \(error.localizedDescription)")
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
      let nsError = error as NSError

      // Ignore cancellation errors as they are expected when user cancels
      if nsError.code == NSURLErrorCancelled {
        return
      }

      // We capture all other errors to Sentry; the SDK configuration in LlamaBarnApp
      // filters out common noise (e.g. offline, connection lost) globally.
      SentrySDK.capture(error: error)

      let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
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

        // Check if we should retry (only for transient network errors)
        if let originalURL, self.shouldRetry(error: nsError, url: originalURL) {
          self.scheduleRetry(url: originalURL, modelId: modelId, resumeData: resumeData)
          return
        }

        // No retry — fail the download
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

        // Clear retry state on final failure
        if let originalURL {
          self.retryAttempts.removeValue(forKey: originalURL)
        }
      }
    }
  }

  // MARK: - Retry Logic

  /// Determines if a failed download should be retried based on error type and attempt count.
  private func shouldRetry(error: NSError, url: URL) -> Bool {
    let attempts = retryAttempts[url] ?? 0
    guard attempts < maxRetryAttempts else { return false }

    // Only retry transient network errors
    let retryableCodes = [
      NSURLErrorTimedOut,
      NSURLErrorNetworkConnectionLost,
      NSURLErrorNotConnectedToInternet,
      NSURLErrorCannotConnectToHost,
      NSURLErrorDNSLookupFailed,
    ]

    return retryableCodes.contains(error.code)
  }

  /// Schedules a retry with exponential backoff.
  private func scheduleRetry(url: URL, modelId: String, resumeData: Data?) {
    let attempts = retryAttempts[url] ?? 0
    retryAttempts[url] = attempts + 1

    // Exponential backoff: 2s, 4s, 8s
    let delay = baseRetryDelay * pow(2.0, Double(attempts))

    logger.info(
      "Scheduling retry \(attempts + 1)/\(self.maxRetryAttempts) for \(url.lastPathComponent) in \(delay)s"
    )

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      // Verify download is still active (user may have cancelled)
      guard self.activeDownloads[modelId] != nil else {
        self.retryAttempts.removeValue(forKey: url)
        return
      }

      let task: URLSessionDownloadTask
      if let resumeData {
        task = self.urlSession.downloadTask(withResumeData: resumeData)
      } else {
        task = self.urlSession.downloadTask(with: self.makeRequest(for: url))
      }
      task.taskDescription = modelId
      task.resume()

      self.logger.info("Retrying download for \(url.lastPathComponent)")
    }
  }

  /// Clears retry state for a URL (called on success or user cancellation).
  private func clearRetryState(for url: URL) {
    retryAttempts.removeValue(forKey: url)
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
      downloadContexts.removeValue(forKey: modelId)
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

  /// Determines which files need downloading for the given model.
  /// Checks both legacy and HF cache locations.
  private func filesRequired(for model: CatalogEntry) -> [URL] {
    // If model is already resolved (installed), no files needed
    if resolvedPaths[model.id] != nil {
      return []
    }

    var files: [URL] = []

    // Main model file — check both legacy and HF cache
    let legacyExists = FileManager.default.fileExists(atPath: model.legacyModelFilePath)
    let hfExists = hfFileExists(model: model, url: model.downloadUrl)
    if !legacyExists && !hfExists {
      files.append(model.downloadUrl)
    }

    // Additional shards
    if let additional = model.additionalParts, !additional.isEmpty {
      let legacyBaseDir = URL(fileURLWithPath: model.legacyModelFilePath)
        .deletingLastPathComponent()
      for url in additional {
        let legacyPath = legacyBaseDir.appendingPathComponent(url.lastPathComponent).path
        let legacyPartExists = FileManager.default.fileExists(atPath: legacyPath)
        let hfPartExists = hfFileExists(model: model, url: url)
        if !legacyPartExists && !hfPartExists {
          files.append(url)
        }
      }
    }

    // Multimodal projection file
    if let mmprojUrl = model.mmprojUrl {
      let legacyMmprojExists: Bool
      if let legacyPath = model.legacyMmprojFilePath {
        legacyMmprojExists = FileManager.default.fileExists(atPath: legacyPath)
      } else {
        legacyMmprojExists = false
      }
      let hfMmprojExists = hfFileExists(model: model, url: mmprojUrl)
      if !legacyMmprojExists && !hfMmprojExists {
        files.append(mmprojUrl)
      }
    }

    return files
  }

  /// Checks if a file exists in the HF cache for a given model and remote URL.
  private func hfFileExists(model: CatalogEntry, url: URL) -> Bool {
    guard let repoDir = model.hfRepoDir else { return false }
    let cacheDir = UserSettings.hfCacheDirectory
    let filename = url.lastPathComponent
    let snapshotsDir =
      cacheDir
      .appendingPathComponent(repoDir)
      .appendingPathComponent("snapshots")

    guard let commits = try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path)
    else {
      return false
    }

    for commit in commits {
      let filePath = snapshotsDir.appendingPathComponent(commit).appendingPathComponent(filename)
      if FileManager.default.fileExists(atPath: filePath.path) {
        return true
      }
    }
    return false
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
    // Use resolved paths if available, otherwise fall back to legacy paths
    let paths: [String]
    if let resolved = resolvedPaths[model.id] {
      paths = resolved.allPaths
    } else {
      paths = model.legacyLocalPaths
    }

    let existingBytes: Int64 = paths.reduce(0) { sum, path in
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

    // Check disk space at the HF cache directory (where new downloads go)
    let targetDir = UserSettings.hfCacheDirectory
    let available = DiskSpace.availableBytes(at: targetDir)

    if available > 0 && remainingBytes > available {
      let needStr = Format.gigabytes(remainingBytes)
      let haveStr = Format.gigabytes(available)
      throw DownloadError.notEnoughDiskSpace(required: needStr, available: haveStr)
    }
  }

  /// Creates a URLRequest for the given URL, adding an Authorization header
  /// with the user's Hugging Face token when downloading from huggingface.co.
  private func makeRequest(for url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    if url.host?.hasSuffix("huggingface.co") == true,
      let token = UserSettings.hfToken
    {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  private func postDownloadsDidChange() {
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }
}
