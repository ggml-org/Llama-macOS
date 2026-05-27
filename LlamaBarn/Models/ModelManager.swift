import Foundation
import Sentry
import os.log

/// Represents the current status of a model
enum ModelStatus: Equatable {
  case available
  case downloading(Progress)
  /// A `.partial` file exists on disk but no transfer is active.
  /// `bytesOnDisk` is the sum of the model's `.partial` file sizes;
  /// `totalBytes` is the resolved-from-HF full size on the `Model` entry.
  case paused(bytesOnDisk: Int64, totalBytes: Int64)
  case installed
}

/// Manages the high-level state of available and downloaded models.
@MainActor
class ModelManager: NSObject, URLSessionDataDelegate {
  static let shared = ModelManager()

  var downloadedModels: [Model] = []

  /// Resolved file paths for each downloaded model, keyed by model ID.
  /// Populated during refreshDownloadedModels(). Used for models.ini generation,
  /// deletion, and determining which files need downloading.
  var resolvedPaths: [String: ResolvedPaths] = [:]

  /// Returns a sorted list of all models that are either installed, currently
  /// downloading, or paused (have a leftover `.partial` dir from a previous
  /// session). This is the primary list shown in the "Installed" section of
  /// the menu.
  var managedModels: [Model] {
    (downloadedModels + downloadingModels + pausedModels)
      .sorted(by: Model.displayOrder(_:_:))
  }

  var downloadingModels: [Model] {
    activeDownloads.values.map { $0.model }
  }

  /// Entries with on-disk `.partial` bytes but no in-flight transfer.
  /// `updateDownloadedModels` excludes ids that are installed or actively
  /// downloading at refresh time.
  var pausedModels: [Model] {
    pausedDownloads.values.map(\.model)
  }

  var activeDownloads: [String: ActiveDownload] = [:]

  /// Looks up a managed model by id. Checks in-flight downloads (which carry
  /// placeholders synthesized by the deeplink handler), the paused map (also
  /// placeholders for paused deeplink installs), then the downloaded list.
  func findManagedModel(id: String) -> Model? {
    if let m = activeDownloads[id]?.model { return m }
    if let m = pausedDownloads[id]?.model { return m }
    return downloadedModels.first { $0.id == id }
  }

  /// Model id → paused-download state (bytes on disk + the `Model` the row
  /// will render from). Sources: `pauseModelDownload` (manually paused this
  /// session) and the internal failure paths (transient failures that
  /// exhausted retries). Carrying the entry here means paused deeplinks
  /// survive teardown without a separate placeholder registry.
  /// Not persisted across restarts — re-clicking the deeplink rebuilds the
  /// placeholder and resumes from the on-disk `.partial` bytes.
  var pausedDownloads: [String: PausedDownload] = [:]

  /// HF download plan per model ID, gathered before download starts.
  /// Contains commit hash and blob hashes needed to write into HF cache layout.
  var downloadPlans: [String: HFDownloadPlan] = [:]

  /// Per-task streaming state for in-flight downloads. Keyed by URLSessionTask.taskIdentifier.
  /// Accessed from both the URLSession delegate queue (nonisolated) and the main actor.
  /// All access is serialized on `writersQueue`, so we opt out of actor isolation here.
  nonisolated(unsafe) private var writers: [Int: PartialWriter] = [:]
  nonisolated private let writersQueue = DispatchQueue(
    label: "app.llamabarn.ModelManager.writers", qos: .userInitiated)

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

    // URLSession delegate callbacks run on a background queue to avoid blocking main thread during
    // file operations. State access is synchronized by dispatching to main queue when needed;
    // writers dict access is guarded by writersQueue.
    let queue = OperationQueue()
    queue.qualityOfService = .userInitiated

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 120  // Temporary network stalls
    config.timeoutIntervalForResource = 60 * 60 * 24  // 24 hours for large files

    urlSession = URLSession(configuration: config, delegate: self, delegateQueue: queue)

    refreshDownloadedModels()
  }

  /// Downloads all required files for a model.
  /// Fetches HF metadata (commit hash, blob hashes) first, then starts URLSession tasks.
  func downloadModel(_ model: Model) throws {
    // Prevent duplicate downloads if user clicks download multiple times or if called from multiple code paths.
    // Without this check, we'd start redundant URLSession tasks, waste bandwidth, and corrupt download state.
    if activeDownloads[model.id] != nil {
      logger.info("Download already in progress for model: \(model.displayName)")
      return
    }

    // Transition paused → downloading. Bytes-on-disk are already in the `.partial`
    // file, so no need to hold them in pausedDownloads once the transfer is live.
    // We do keep the byte count around to pre-seed the placeholder Progress below —
    // without it, the row flashes 0% while HF metadata is being fetched (before
    // writers open and `refreshProgress` can re-derive the real figure).
    let resumedBytes = pausedDownloads.removeValue(forKey: model.id)?.bytesOnDisk ?? 0

    let filesToDownload = try prepareDownload(for: model)
    guard !filesToDownload.isEmpty else { return }

    logger.info("Starting download for model: \(model.displayName)")

    // Add placeholder entry immediately so the model appears as "downloading"
    // in the UI before the async HF metadata fetch completes. Seed completedUnitCount
    // from the resumed bytes so the first refresh shows the correct percentage; the
    // value matches what `ActiveDownload.refreshProgress` will compute once writers open
    // (completedFilesBytes=0 + activeBytes=existing partial bytes), so there's no jump.
    let modelId = model.id
    let totalUnitCount = max(remainingBytesRequired(for: model), 1)
    let progress = Progress(totalUnitCount: totalUnitCount)
    progress.completedUnitCount = min(resumedBytes, totalUnitCount)
    activeDownloads[modelId] = ActiveDownload(
      model: model,
      progress: progress,
      tasks: [:],
      completedFilesBytes: 0
    )
    postDownloadsDidChange()

    // Fetch HF metadata before starting download tasks.
    // HF cache is the only download destination; if metadata fetch fails, we abort —
    // there's no legacy flat fallback anymore.
    Task {
      let plan = await self.fetchHFDownloadPlan(for: model)
      await MainActor.run {
        guard let plan else {
          self.logger.error("HF metadata fetch failed for \(model.displayName); aborting download")
          self.tearDownActiveDownload(modelId: modelId, outcome: .pause)
          NotificationCenter.default.post(
            name: .LBModelDownloadDidFail,
            object: self,
            userInfo: [
              "model": model,
              "error":
                "Couldn't reach Hugging Face to start the download. This is usually a temporary rate limit or outage — try again in a few minutes, or set a Hugging Face token in Settings to lift the limit.",
            ]
          )
          return
        }
        self.downloadPlans[modelId] = plan
        self.logger.info("HF download plan ready for \(model.displayName): \(plan.repoDir)")
        self.startDownloadTasks(model: model, files: filesToDownload)
      }
    }
  }

  /// Starts URLSession data tasks for the given files.
  /// Each file streams into a `.partial` file under `<hf-cache>/.llamabarn-partial/<modelId>/`;
  /// if a partial already exists on disk, we resume via a `Range` header.
  private func startDownloadTasks(model: Model, files: [URL]) {
    let modelId = model.id
    guard let plan = downloadPlans[modelId] else {
      logger.error("Missing HF download plan when starting tasks for \(model.displayName)")
      tearDownActiveDownload(modelId: modelId, outcome: .pause)
      return
    }
    let cacheDir = UserSettings.hfCacheDirectory
    let totalUnitCount = max(remainingBytesRequired(for: model), 1)
    var aggregate = ActiveDownload(
      model: model,
      progress: Progress(totalUnitCount: totalUnitCount),
      tasks: [:],
      completedFilesBytes: 0
    )

    for fileUrl in files {
      do {
        let writer = try openPartialWriter(
          modelId: modelId, cacheDir: cacheDir, url: fileUrl, plan: plan)
        let task = makeDataTask(for: fileUrl, modelId: modelId, writer: writer)
        writersQueue.sync { writers[task.taskIdentifier] = writer }
        aggregate.addTask(task)
        task.resume()
      } catch {
        logger.error(
          "Failed to open partial for \(fileUrl.lastPathComponent): \(error.localizedDescription)")
        // Abort the whole model download — we can't proceed with a missing partial.
        // Cancel any tasks already started for this model.
        activeDownloads[modelId] = aggregate
        tearDownActiveDownload(modelId: modelId, outcome: .pause)
        NotificationCenter.default.post(
          name: .LBModelDownloadDidFail, object: self,
          userInfo: [
            "model": model,
            "error": "Couldn't open staging file: \(error.localizedDescription)",
          ]
        )
        return
      }
    }

    activeDownloads[modelId] = aggregate
    refreshProgress(modelId: modelId)
    postDownloadsDidChange()
  }

  /// Builds a URLSessionDataTask for a remote file. Adds a `Range: bytes=N-` header when
  /// the writer's on-disk `.partial` already has N bytes.
  private func makeDataTask(
    for url: URL, modelId: String, writer: PartialWriter
  ) -> URLSessionDataTask {
    var request = makeRequest(for: url)
    if writer.bytesWritten > 0 {
      request.setValue("bytes=\(writer.bytesWritten)-", forHTTPHeaderField: "Range")
      logger.info(
        "Resuming \(url.lastPathComponent) from byte \(writer.bytesWritten)")
    }
    let task = urlSession.dataTask(with: request)
    task.taskDescription = modelId
    return task
  }

  /// Opens (or creates) the `.partial` file for a remote URL and rebuilds the running SHA256
  /// hash over any already-present prefix. The re-hash cost is bounded by existing file size,
  /// which is small relative to the remaining download.
  private func openPartialWriter(
    modelId: String, cacheDir: URL, url: URL, plan: HFDownloadPlan
  ) throws -> PartialWriter {
    // `filename` is repo-relative (e.g. `Q4_K_M/model.gguf`), not just a basename,
    // so `writeBlobAndLink` places the snapshot symlink at the correct nested
    // path. Entries whose download URL already points at a flat filename fall
    // through to `lastPathComponent`, same value as before — no behavior change.
    let filename = HFCache.repoRelativePath(from: url) ?? url.lastPathComponent
    let partialURL = HFCache.partialPath(cacheDir: cacheDir, modelId: modelId, filename: filename)
    let dir = partialURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Stat existing partial (0 if absent). Create empty file if missing so FileHandle(forWritingTo:) works.
    let existing: Int64
    if FileManager.default.fileExists(atPath: partialURL.path) {
      let attrs = try FileManager.default.attributesOfItem(atPath: partialURL.path)
      existing = (attrs[.size] as? NSNumber)?.int64Value ?? 0
    } else {
      FileManager.default.createFile(atPath: partialURL.path, contents: nil)
      existing = 0
    }

    let handle = try FileHandle(forWritingTo: partialURL)
    try handle.seekToEnd()

    let hasher = HFCache.SHA256Hasher()
    if existing > 0 {
      try HFCache.feedHasher(hasher, from: partialURL)
    }

    return PartialWriter(
      modelId: modelId, url: url, filename: filename,
      partialURL: partialURL, handle: handle, hasher: hasher,
      bytesWritten: existing,
      expectedBlobHash: plan.blobHashes[url]
    )
  }

  /// Fetches HF file metadata (commit hash, blob hashes) for a model via HEAD requests.
  /// Each HEAD request returns both X-Repo-Commit and X-Linked-Etag, so one request
  /// per file gives us everything we need. Returns nil on failure (caller aborts download).
  private nonisolated func fetchHFDownloadPlan(for model: Model) async -> HFDownloadPlan? {
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

    return HFDownloadPlan(repoDir: repoDir, commit: commit, blobHashes: blobHashes)
  }

  /// Gets the current status of a model.
  func status(for model: Model) -> ModelStatus {
    if downloadedModels.contains(where: { $0.id == model.id }) {
      return .installed
    }
    if let download = activeDownloads[model.id] {
      return .downloading(download.progress)
    }
    if let paused = pausedDownloads[model.id] {
      return .paused(bytesOnDisk: paused.bytesOnDisk, totalBytes: model.fileSize)
    }
    return .available
  }

  /// Safely deletes a downloaded model and its associated files.
  func deleteDownloadedModel(_ model: Model) {
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
    let modelId = model.id
    let cacheDir = UserSettings.hfCacheDirectory
    Task.detached {
      do {
        // Clean up any lingering partial files for this model.
        HFCache.removePartials(cacheDir: cacheDir, modelId: modelId)

        if let paths {
          try HFCache.deleteModelFiles(
            cacheDir: cacheDir,
            repoDir: paths.hfRepoDirName,
            paths: paths
          )
        }
      } catch {
        // If deletion failed, restore the model in the list
        await MainActor.run {
          Self.restoreDeletedModel(model, logger: logger, error: error)
        }
      }
    }
  }

  private static func restoreDeletedModel(_ model: Model, logger: Logger, error: Error) {
    let manager = ModelManager.shared
    manager.downloadedModels.append(model)
    manager.downloadedModels.sort(by: Model.displayOrder(_:_:))
    // Re-scan to rebuild resolvedPaths
    manager.refreshDownloadedModels()
    logger.error("Failed to delete model: \(error.localizedDescription)")
  }

  /// Updates the `models.ini` file required for using llama-server in Router Mode.
  /// Returns true if the file was changed, false if content was identical.
  @discardableResult
  func updateModelsFile() -> Bool {
    let content = generateModelsFileContent()
    let destinationURL = UserSettings.appSupportDir.appendingPathComponent("models.ini")

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

      guard let paths = resolvedPaths[model.id] else { continue }
      let modelPath = paths.modelFile
      let mmprojPath = paths.mmprojFile

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

      content += "\n"
    }
    return content
  }

  /// Active mem-profile enrichment task. Cancelled on refresh to avoid stale updates.
  private var memProfileTask: Task<Void, Never>?

  /// Scans the HF cache for installed models. Every model is treated as a
  /// sideloaded discovery — metadata comes from the repo dir + filename.
  func refreshDownloadedModels() {
    let hfCacheDir = UserSettings.hfCacheDirectory

    // Move directory reading to background queue to avoid blocking main thread
    Task.detached {
      let discovered = HFCache.scanForSideloaded(cacheDir: hfCacheDir)

      // Apply cached mem-profile when available; queue the rest for async probing.
      var resolvedPaths: [String: ResolvedPaths] = [:]
      var models: [Model] = []
      var needsProfile: [(id: String, path: String)] = []
      for (entry, paths) in discovered {
        var entry = entry
        if let cached = MemProfileCache.get(modelId: entry.id) {
          entry.ctxBytesPer1kTokens = cached.ctxBytesPer1kTokens
          entry.residentBytes = cached.residentBytes
        } else {
          needsProfile.append((id: entry.id, path: paths.modelFile))
        }
        resolvedPaths[entry.id] = paths
        models.append(entry)
      }

      // Garbage-collect partial dirs whose target is now installed.
      let installedIds = Set(models.map(\.id))
      HFCache.cleanInstalledPartials(cacheDir: hfCacheDir, installedIds: installedIds)

      let allDownloaded = models
      let finalResolved = resolvedPaths
      let pendingProfile = needsProfile

      await MainActor.run {
        Self.updateDownloadedModels(
          allDownloaded, resolved: finalResolved, pending: pendingProfile)
      }
    }
  }

  private static func updateDownloadedModels(
    _ models: [Model],
    resolved: [String: ResolvedPaths],
    pending: [(id: String, path: String)] = []
  ) {
    let manager = ModelManager.shared
    manager.downloadedModels = models.sorted(by: Model.displayOrder(_:_:))
    manager.resolvedPaths = resolved
    // Paused-download entries are entirely in-memory (placeholders the
    // deeplink/manual-pause paths stash). A refresh shouldn't touch them
    // unless the row is now installed or actively downloading.
    let excluded = Set(manager.downloadedModels.map(\.id))
      .union(manager.activeDownloads.keys)
    manager.pausedDownloads = manager.pausedDownloads.filter { !excluded.contains($0.key) }

    // Only reload server if models.ini actually changed
    if manager.updateModelsFile() {
      LlamaServer.shared.reload()
    }

    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: manager)

    // Kick off async mem-profile probing for models without cached results
    if !pending.isEmpty {
      manager.enrichWithMemProfiles(pending)
    }
  }

  /// Probes sideloaded models that don't have a cached MemProfile.
  /// Updates each model's ctxBytesPer1kTokens as results come in, refreshing the UI.
  /// Runs sequentially (one model at a time) to avoid GPU contention.
  private func enrichWithMemProfiles(_ models: [(id: String, path: String)]) {
    // Cancel any previous enrichment task (e.g. from a previous refresh).
    // The withTaskCancellationHandler in MemProfileRunner.run() ensures the
    // subprocess is terminated when the task is cancelled.
    memProfileTask?.cancel()

    memProfileTask = Task.detached { [weak self] in
      for (modelId, modelPath) in models {
        guard !Task.isCancelled else { return }

        let profile = await MemProfileRunner.run(modelPath: modelPath)
        guard !Task.isCancelled else { return }

        // On failure, use a sentinel (-1) in memory so the UI drops out of
        // "estimating..." for this session — but don't persist it. A transient
        // failure (e.g. a broken-build window after a llama.cpp update where
        // llama-fit-params can't dyld-link) would otherwise stick across
        // launches and never re-probe. Cost of not persisting: a few seconds
        // of "estimating..." next launch for genuinely unprobable models.
        let resolved = profile ?? MemProfile(ctxBytesPer1kTokens: -1)

        // Only cache successful probes to disk.
        if profile != nil {
          MemProfileCache.set(resolved, for: modelId)
        }

        // Update the in-memory model entry and refresh the UI
        guard let mgr = self else { return }
        await MainActor.run {
          if let idx = mgr.downloadedModels.firstIndex(where: { $0.id == modelId }) {
            mgr.downloadedModels[idx].ctxBytesPer1kTokens = resolved.ctxBytesPer1kTokens
            mgr.downloadedModels[idx].residentBytes = resolved.residentBytes
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

  /// Discards an ongoing or paused download — removes `.partial` files, clears
  /// bookkeeping. A subsequent start begins from byte zero.
  func cancelModelDownload(_ model: Model) {
    tearDownActiveDownload(modelId: model.id, outcome: .discard)
  }

  /// Stops an in-flight download but keeps the `.partial` bytes on disk so the user
  /// can resume it later. The model reappears in the Installed section as paused.
  func pauseModelDownload(_ model: Model) {
    guard activeDownloads[model.id] != nil else { return }
    tearDownActiveDownload(modelId: model.id, outcome: .pause)
  }

  // MARK: - Convenience Methods

  /// Returns true if the model is installed (fully downloaded).
  func isInstalled(_ model: Model) -> Bool {
    status(for: model) == .installed
  }

  /// Returns true if the model is currently downloading.
  func isDownloading(_ model: Model) -> Bool {
    if case .downloading = status(for: model) { return true }
    return false
  }

  // MARK: - URLSessionDataDelegate

  nonisolated func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    // `findManagedModel` runs on the main actor — we already bounce to main
    // elsewhere in this delegate (e.g. `UserSettings.hfCacheDirectory` on the
    // 416 path), so one more sync hop is consistent with the existing shape.
    guard let modelId = dataTask.taskDescription,
      let model = DispatchQueue.main.sync(execute: {
        ModelManager.shared.findManagedModel(id: modelId)
      }),
      let http = response as? HTTPURLResponse
    else {
      completionHandler(.cancel)
      return
    }

    let status = http.statusCode

    // 416 Range Not Satisfiable — partial is already at or past the remote's size.
    // Short-circuit: cancel the transfer (no body needed) and finalize what's on disk.
    if status == 416 {
      let writer: PartialWriter? = writersQueue.sync {
        writers.removeValue(forKey: dataTask.taskIdentifier)
      }
      completionHandler(.cancel)
      if let writer {
        logger.info(
          "416 for \(writer.filename); partial appears complete, finalizing")
        finalizeTask(
          modelId: modelId, model: model, writer: writer, dataTask: dataTask)
      }
      return
    }

    // Non-success statuses: fail the download with a user-facing message.
    if !(200...299).contains(status) {
      let message = userMessage(forHTTPStatus: status)
      // 401/403/404 are permanent — remove partials so a later retry doesn't replay a bad state.
      if [401, 403, 404].contains(status) {
        let cacheDir = DispatchQueue.main.sync { UserSettings.hfCacheDirectory }
        HFCache.removePartials(cacheDir: cacheDir, modelId: modelId)
      }
      let writer: PartialWriter? = writersQueue.sync {
        writers.removeValue(forKey: dataTask.taskIdentifier)
      }
      writer?.closeHandle()

      // Keep Sentry error-grouping stable across releases.
      let nsErr = NSError(
        domain: "LlamaBarn.ModelManager", code: status,
        userInfo: [
          NSLocalizedDescriptionKey: "Download failed with HTTP \(status)",
          "modelId": modelId,
          "url": dataTask.originalRequest?.url?.absoluteString ?? "unknown",
        ])
      SentrySDK.capture(error: nsErr)
      completionHandler(.cancel)
      handleDownloadFailure(modelId: modelId, model: model, reason: message)
      return
    }

    // 200 OK — server ignored our Range request (or we didn't send one).
    // Restart the file: truncate, reset the running hash, reset byte counter.
    if status == 200 {
      writersQueue.sync {
        guard let writer = writers[dataTask.taskIdentifier] else { return }
        if writer.bytesWritten > 0 {
          logger.warning(
            "Server ignored Range for \(writer.filename); restarting from byte 0")
        }
        try? writer.handle.truncate(atOffset: 0)
        try? writer.handle.seek(toOffset: 0)
        writer.bytesWritten = 0
        writer.hasher = HFCache.SHA256Hasher()
      }
    }

    // Both 200 and 206 yield a full-size; stash it for progress tracking.
    let fullSize = extractFullSize(from: http, status: status)
    if fullSize > 0 {
      writersQueue.sync {
        writers[dataTask.taskIdentifier]?.totalExpected = fullSize
      }
    }

    DispatchQueue.main.async { [weak self] in
      self?.refreshProgress(modelId: modelId)
    }
    completionHandler(.allow)
  }

  nonisolated func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
  ) {
    var writeFailed = false
    writersQueue.sync {
      guard let writer = writers[dataTask.taskIdentifier] else { return }
      do {
        try writer.handle.write(contentsOf: data)
        writer.hasher.update(data)
        writer.bytesWritten += Int64(data.count)
      } catch {
        logger.error(
          "Write failed for \(writer.filename): \(error.localizedDescription)")
        writeFailed = true
      }
    }
    if writeFailed {
      // Cancel this task; didCompleteWithError will handle the failure path (including
      // Sentry capture). Do not treat cancellation itself as success.
      dataTask.cancel()
      return
    }

    guard let modelId = dataTask.taskDescription else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let now = Date()
      let lastTime = self.lastNotificationTime[modelId] ?? .distantPast
      if now.timeIntervalSince(lastTime) >= self.notificationThrottleInterval {
        self.lastNotificationTime[modelId] = now
        self.refreshProgress(modelId: modelId)
        self.postDownloadsDidChange()
      }
    }
  }

  nonisolated func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    // See note in the `didReceive` delegate above on the main-actor hop.
    guard let modelId = task.taskDescription,
      let model = DispatchQueue.main.sync(execute: {
        ModelManager.shared.findManagedModel(id: modelId)
      }),
      let dataTask = task as? URLSessionDataTask
    else { return }

    if let error {
      let nsError = error as NSError
      // Always drop the writer so its file handle is closed before anything else touches the file.
      let writer: PartialWriter? = writersQueue.sync {
        writers.removeValue(forKey: task.taskIdentifier)
      }
      writer?.closeHandle()

      // Cancelled: either user cancel or our own short-circuit (416 / HTTP error already handled).
      // In both cases we've already done the cleanup or it doesn't apply.
      if nsError.code == NSURLErrorCancelled {
        return
      }

      // Capture remaining errors to Sentry; the SDK config in LlamaBarnApp filters common noise.
      SentrySDK.capture(error: error)

      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.logger.error("Model download failed: \(error.localizedDescription)")

        // Retry transient network errors (partial file is the resume state).
        if let originalURL = task.originalRequest?.url,
          self.shouldRetry(error: nsError, url: originalURL)
        {
          self.scheduleRetry(url: originalURL, modelId: modelId)
          return
        }

        if self.activeDownloads[modelId] != nil {
          _ = self.updateActiveDownload(modelId: modelId) { agg in
            agg.removeTask(with: task.taskIdentifier)
          }
          self.refreshProgress(modelId: modelId)
          self.postDownloadsDidChange()
          NotificationCenter.default.post(
            name: .LBModelDownloadDidFail, object: self,
            userInfo: ["model": model, "error": error.localizedDescription]
          )
        }

        // Clear retry state on final failure.
        if let originalURL = task.originalRequest?.url {
          self.retryAttempts.removeValue(forKey: originalURL)
        }
      }
      return
    }

    // Success: promote the `.partial` into the HF cache.
    let writer: PartialWriter? = writersQueue.sync {
      writers.removeValue(forKey: task.taskIdentifier)
    }
    guard let writer else { return }  // already handled (e.g. 416 path)
    finalizeTask(modelId: modelId, model: model, writer: writer, dataTask: dataTask)
  }

  /// Hashes, verifies, and promotes a completed `.partial` file into `blobs/<sha256>`.
  /// Runs on the delegate queue (background). Never on the main queue — we do file I/O here.
  nonisolated private func finalizeTask(
    modelId: String, model: Model,
    writer: PartialWriter, dataTask: URLSessionDataTask
  ) {
    writer.closeHandle()

    let fileSize: Int64 = {
      if let attrs = try? FileManager.default.attributesOfItem(atPath: writer.partialURL.path) {
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
      }
      return 0
    }()

    // Sanity check: reject obviously broken downloads (error pages, empty files).
    // We don't require an exact size match — expected sizes can drift when HF re-uploads.
    let minThreshold: Int64 = 1_000_000
    if fileSize <= minThreshold {
      try? FileManager.default.removeItem(at: writer.partialURL)
      handleDownloadFailure(
        modelId: modelId, model: model,
        reason: "file too small (\(fileSize) B)")
      return
    }

    // Digest from the running hasher (covers existing-prefix re-hash at open time, plus streamed bytes).
    let computed = writer.hasher.finalize()
    if let expected = writer.expectedBlobHash, expected != computed {
      logger.error(
        "Hash mismatch for \(writer.filename): expected \(expected), got \(computed)")
      try? FileManager.default.removeItem(at: writer.partialURL)
      handleDownloadFailure(
        modelId: modelId, model: model,
        reason: "File verification failed — the partial download was corrupt. Try again."
      )
      return
    }
    let blobHash = writer.expectedBlobHash ?? computed

    // Fetch HF download plan (commit/repoDir) on main actor.
    let plan: HFDownloadPlan? = DispatchQueue.main.sync {
      self.downloadPlans[modelId]
    }
    guard let plan else {
      handleDownloadFailure(
        modelId: modelId, model: model,
        reason: "Missing Hugging Face metadata for \(model.displayName).")
      return
    }
    let cacheDir = DispatchQueue.main.sync { UserSettings.hfCacheDirectory }

    do {
      try HFCache.writeBlobAndLink(
        cacheDir: cacheDir, repoDir: plan.repoDir, commit: plan.commit,
        blobHash: blobHash, filename: writer.filename,
        from: writer.partialURL)
    } catch {
      logger.error(
        "Failed to promote partial \(writer.filename): \(error.localizedDescription)")
      handleDownloadFailure(
        modelId: modelId, model: model, reason: error.localizedDescription)
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.clearRetryState(for: writer.url)

      let wasCompleted = self.updateActiveDownload(modelId: modelId) { agg in
        agg.markTaskFinished(dataTask, fileSize: fileSize)
      }
      if wasCompleted {
        self.logger.info("All downloads completed for model: \(model.displayName)")
        self.downloadPlans.removeValue(forKey: modelId)
        // Clean up the now-empty partial dir (the file itself moved to blobs).
        HFCache.removePartials(cacheDir: cacheDir, modelId: modelId)
        self.refreshDownloadedModels()
      } else {
        self.refreshProgress(modelId: modelId)
      }
      self.postDownloadsDidChange()
    }
  }

  nonisolated private func handleDownloadFailure(
    modelId: String, model: Model, reason: String
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.logger.error("Model download failed (\(reason)) for model: \(model.displayName)")
      self.tearDownActiveDownload(modelId: modelId, outcome: .pause)
      NotificationCenter.default.post(
        name: .LBModelDownloadDidFail,
        object: self,
        userInfo: ["model": model, "error": reason]
      )
    }
  }

  /// Maps HTTP status codes to user-facing guidance. We deliberately don't claim a
  /// specific cause (rate limit vs. gated repo vs. CDN outage) — Hugging Face uses
  /// these codes for several reasons, so we hedge with "usually" and point the user
  /// at the most common remedy.
  nonisolated private func userMessage(forHTTPStatus status: Int) -> String {
    switch status {
    case 401:
      return
        "Hugging Face requires authentication for this download. Set a Hugging Face token in Settings and try again."
    case 403, 429:
      return
        "Hugging Face refused the download (HTTP \(status)). This usually means a rate limit — try again in a few minutes, or set a Hugging Face token in Settings to lift the limit."
    case 404:
      return
        "Hugging Face returned 404 for this file. The repo may have moved or been removed."
    case 500...599:
      return
        "Hugging Face is temporarily unavailable (HTTP \(status)). Try again in a few minutes."
    default:
      return "Download failed with HTTP \(status)."
    }
  }

  /// Extracts the full (not just remaining) size of the remote file from the response.
  /// For 206 responses we parse `Content-Range: bytes X-Y/Z`; for 200 we fall back to `Content-Length`.
  /// Returns 0 when neither header is present / parseable.
  nonisolated private func extractFullSize(
    from response: HTTPURLResponse, status: Int
  ) -> Int64 {
    if status == 206, let cr = response.value(forHTTPHeaderField: "Content-Range") {
      // Format: "bytes X-Y/Z" (Z may be "*" when total is unknown).
      if let slash = cr.firstIndex(of: "/") {
        let totalStr = cr[cr.index(after: slash)...]
          .trimmingCharacters(in: .whitespaces)
        if totalStr != "*", let total = Int64(totalStr) { return total }
      }
    }
    if let lenStr = response.value(forHTTPHeaderField: "Content-Length"),
      let len = Int64(lenStr)
    {
      return len
    }
    return 0
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

  /// Schedules a retry with exponential backoff. The partial file on disk is our resume state,
  /// so all we need to do is re-open a writer and issue a fresh Range request.
  private func scheduleRetry(url: URL, modelId: String) {
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
      guard let model = self.activeDownloads[modelId]?.model
      else {
        self.retryAttempts.removeValue(forKey: url)
        return
      }

      self.logger.info("Retrying download for \(url.lastPathComponent)")
      self.restartTask(model: model, url: url)
    }
  }

  /// Restarts a single URL within an active download (used by retries).
  /// Re-opens the `.partial` writer and issues a fresh Range request.
  /// If we can't re-open the partial file, fail the whole model download rather than
  /// leave it hanging in `.downloading` with no forward progress.
  private func restartTask(model: Model, url: URL) {
    guard let plan = downloadPlans[model.id] else { return }
    let cacheDir = UserSettings.hfCacheDirectory
    do {
      let writer = try openPartialWriter(
        modelId: model.id, cacheDir: cacheDir, url: url, plan: plan)
      let task = makeDataTask(for: url, modelId: model.id, writer: writer)
      writersQueue.sync { writers[task.taskIdentifier] = writer }
      _ = updateActiveDownload(modelId: model.id) { agg in
        agg.addTask(task)
      }
      task.resume()
    } catch {
      logger.error(
        "Retry failed to open partial for \(url.lastPathComponent): \(error.localizedDescription)"
      )
      handleDownloadFailure(
        modelId: model.id, model: model,
        reason: "Couldn't reopen staging file for retry: \(error.localizedDescription)"
      )
    }
  }

  /// Clears retry state for a URL (called on success or user cancellation).
  private func clearRetryState(for url: URL) {
    retryAttempts.removeValue(forKey: url)
  }

  // MARK: - Helpers

  /// Cancels every in-flight URLSession task for a model and closes its writers.
  /// Does NOT delete partial files — that's a separate decision (user cancel vs. failure).
  private func cancelTasks(for modelId: String) {
    guard let download = activeDownloads[modelId] else { return }
    let taskIds = Array(download.tasks.keys)
    for task in download.tasks.values {
      task.cancel()
    }
    // Drop writers and close their handles synchronously so the partial files aren't held open.
    writersQueue.sync {
      for id in taskIds {
        if let w = writers.removeValue(forKey: id) {
          w.closeHandle()
        }
      }
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

  /// What to do with the on-disk `.partial` bytes when tearing down an active download.
  private enum TeardownOutcome {
    /// User asked to throw the download away — remove partials, drop any paused state.
    case discard
    /// Stop the transfer but keep partials so the model shows up as paused.
    /// Used by the user "pause" action and by internal failure paths — if the failure
    /// cleanup already deleted the file (401/403/404, hash mismatch, too-small), the
    /// paused entry is skipped and the row simply disappears.
    case pause
  }

  /// Stops every in-flight URLSession task for a model, clears in-memory bookkeeping,
  /// and either surfaces the leftover bytes as a paused row or discards them.
  /// The single teardown path means cancel, pause, and internal failure all behave
  /// identically except for what happens to the `.partial` files.
  private func tearDownActiveDownload(modelId: String, outcome: TeardownOutcome) {
    let model = activeDownloads[modelId]?.model

    if activeDownloads[modelId] != nil {
      cancelTasks(for: modelId)
      activeDownloads.removeValue(forKey: modelId)
      lastNotificationTime.removeValue(forKey: modelId)
      downloadPlans.removeValue(forKey: modelId)
      // Clear retry counters — a subsequent resume/retry should start a fresh budget.
      if let model {
        for url in model.allDownloadUrls { clearRetryState(for: url) }
      }
    }

    switch outcome {
    case .discard:
      pausedDownloads.removeValue(forKey: modelId)
      HFCache.removePartials(cacheDir: UserSettings.hfCacheDirectory, modelId: modelId)
    case .pause:
      let bytes = HFCache.partialBytes(
        cacheDir: UserSettings.hfCacheDirectory, modelId: modelId)
      if bytes > 0, let model {
        pausedDownloads[modelId] = PausedDownload(model: model, bytesOnDisk: bytes)
      } else {
        // Failure path already wiped the partials (e.g. 404, hash mismatch) — nothing
        // to resume, so don't leave a ghost entry in pausedDownloads.
        pausedDownloads.removeValue(forKey: modelId)
      }
    }

    // Every teardown changes the Installed section shape AND progress state.
    // Posting here keeps the three callers (cancel / pause / internal failure)
    // from having to remember to fire the right notifications.
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
  }

  /// Recomputes the aggregate progress for a model from its per-task writer state.
  /// Safe to call from the main actor at any time.
  private func refreshProgress(modelId: String) {
    guard var download = activeDownloads[modelId] else { return }
    let taskIds = Array(download.tasks.keys)
    let (active, expected) = writersQueue.sync { () -> (Int64, Int64) in
      var a: Int64 = 0
      var e: Int64 = 0
      for id in taskIds {
        if let w = writers[id] {
          a += w.bytesWritten
          e += w.totalExpected > 0 ? w.totalExpected : w.bytesWritten
        }
      }
      return (a, e)
    }
    download.refreshProgress(activeBytes: active, expectedActiveBytes: expected)
    activeDownloads[modelId] = download
  }

  private func prepareDownload(for model: Model) throws -> [URL] {
    let filesToDownload = filesRequired(for: model)
    guard !filesToDownload.isEmpty else { return [] }

    try validateCompatibility(for: model)

    let remainingBytes = remainingBytesRequired(for: model)
    try validateDiskSpace(for: model, remainingBytes: remainingBytes)

    return filesToDownload
  }

  /// Determines which files need downloading for the given model.
  private func filesRequired(for model: Model) -> [URL] {
    if resolvedPaths[model.id] != nil { return [] }

    var files: [URL] = []
    if !hfFileExists(model: model, url: model.downloadUrl) {
      files.append(model.downloadUrl)
    }
    if let additional = model.additionalParts {
      for url in additional where !hfFileExists(model: model, url: url) {
        files.append(url)
      }
    }
    if let mmprojUrl = model.mmprojUrl, !hfFileExists(model: model, url: mmprojUrl) {
      files.append(mmprojUrl)
    }

    return files
  }

  /// Checks if a file exists in the HF cache for a given model and remote URL.
  private func hfFileExists(model: Model, url: URL) -> Bool {
    guard let repoDir = model.hfRepoDir else { return false }
    let cacheDir = UserSettings.hfCacheDirectory
    let filename = HFCache.repoRelativePath(from: url) ?? url.lastPathComponent
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

  private func validateCompatibility(for model: Model) throws {
    guard model.isCompatible() else {
      let reason =
        model.incompatibilitySummary()
        ?? "isn't compatible with this Mac's memory."
      throw DownloadError.notCompatible(reason: reason)
    }
  }

  private func remainingBytesRequired(for model: Model) -> Int64 {
    let paths = resolvedPaths[model.id]?.allPaths ?? []
    let existingBytes: Int64 = paths.reduce(0) { sum, path in
      guard FileManager.default.fileExists(atPath: path),
        let attrs = try? FileManager.default.attributesOfItem(atPath: path),
        let size = (attrs[.size] as? NSNumber)?.int64Value
      else { return sum }
      return sum + size
    }
    return max(model.fileSize - existingBytes, 0)
  }

  private func validateDiskSpace(for model: Model, remainingBytes: Int64) throws {
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

// MARK: - PartialWriter

/// Per-file streaming state: open `.partial` file handle, running SHA256 hash,
/// byte counters, and the expected blob hash when known.
///
/// Reference type so URLSession delegate callbacks can mutate fields without re-storing
/// into the `writers` dict. All access is serialized on `ModelManager.writersQueue`, so
/// it's safe across the main actor / delegate queue boundary — hence `@unchecked Sendable`.
final class PartialWriter: @unchecked Sendable {
  let modelId: String
  let url: URL
  let filename: String
  let partialURL: URL
  let handle: FileHandle
  /// Running hash over bytes present on disk. Replaced (not reset in place) when the
  /// server responds 200 and we truncate the partial.
  var hasher: HFCache.SHA256Hasher
  /// Bytes currently on disk in the `.partial` file (= our running hash's input length).
  var bytesWritten: Int64
  /// Full size of the remote file once known from Content-Range / Content-Length.
  /// 0 before the response arrives.
  var totalExpected: Int64
  /// SHA256 of the blob as advertised by HF (`X-Linked-Etag`), when available.
  /// Nil → we trust the computed digest instead.
  let expectedBlobHash: String?

  init(
    modelId: String, url: URL, filename: String, partialURL: URL,
    handle: FileHandle, hasher: HFCache.SHA256Hasher,
    bytesWritten: Int64, expectedBlobHash: String?
  ) {
    self.modelId = modelId
    self.url = url
    self.filename = filename
    self.partialURL = partialURL
    self.handle = handle
    self.hasher = hasher
    self.bytesWritten = bytesWritten
    self.totalExpected = 0
    self.expectedBlobHash = expectedBlobHash
  }

  func closeHandle() {
    try? handle.close()
  }
}
