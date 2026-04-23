import Foundation
import Sentry
import os.log

/// Represents the current status of a model
enum ModelStatus: Equatable {
  case available
  case downloading(Progress)
  /// A `.partial` file exists on disk from a previous session but no transfer is active.
  /// `bytesOnDisk` is the sum of the model's `.partial` file sizes; `totalBytes` is the
  /// catalog-declared full size.
  case paused(bytesOnDisk: Int64, totalBytes: Int64)
  case installed
}

/// Manages the high-level state of available and downloaded models.
@MainActor
class ModelManager: NSObject, URLSessionDataDelegate {
  static let shared = ModelManager()

  var downloadedModels: [CatalogEntry] = []

  /// Resolved file paths for each downloaded model, keyed by model ID.
  /// Populated during refreshDownloadedModels(). Used for models.ini generation,
  /// deletion, and determining which files need downloading.
  var resolvedPaths: [String: ResolvedPaths] = [:]

  /// Returns a sorted list of all models that are either installed, currently downloading,
  /// paused (have a leftover `.partial` dir from a previous session), or pending
  /// from a `llamabarn://` deeplink that hasn't started transferring yet.
  /// This is the primary list shown in the "Installed" section of the menu.
  var managedModels: [CatalogEntry] {
    let covered = Set(
      downloadedModels.map(\.id) + downloadingModels.map(\.id) + pausedModels.map(\.id))
    let stalePending = pendingInstalls.values.filter { !covered.contains($0.id) }
    return (downloadedModels + downloadingModels + pausedModels + stalePending)
      .sorted(by: CatalogEntry.displayOrder(_:_:))
  }

  var downloadingModels: [CatalogEntry] {
    activeDownloads.values.map { $0.model }
  }

  /// Catalog or pending entries with on-disk `.partial` bytes but no in-flight
  /// transfer. `pausedDownloads` is kept in sync so this is just a lookup map;
  /// no defensive filtering needed — `updateDownloadedModels` excludes ids that
  /// are installed or actively downloading at refresh time.
  var pausedModels: [CatalogEntry] {
    pausedDownloads.keys.compactMap { findManagedModel(id: $0) }
  }

  var activeDownloads: [String: ActiveDownload] = [:]

  /// Pending sideload installs originated by `llamabarn://` deeplinks.
  /// Keyed by the stable sideloaded id `"{org}/{repo}:{QUANT}"` — same shape
  /// `HFCache.buildSideloadedEntry` produces, so identity survives the handoff
  /// to `scanForSideloaded` once the download lands.
  /// Persisted to `UserDefaults` via `PendingInstallStore` so pending rows
  /// reappear after relaunch.
  var pendingInstalls: [String: CatalogEntry] = [:]

  /// Catalog-first, then pending deeplinks, then already-downloaded sideloaded
  /// entries. Used anywhere we need to resolve a model id back to a
  /// `CatalogEntry` — paused-row resolution, URLSession delegate callbacks,
  /// partial-scan allowlist.
  func findManagedModel(id: String) -> CatalogEntry? {
    if let m = Catalog.findModel(id: id) { return m }
    if let m = pendingInstalls[id] { return m }
    return downloadedModels.first { $0.id == id }
  }

  /// Model id → bytes on disk in the `.partial` staging dir, for any download that
  /// isn't currently transferring. Sources: the init scan (interrupted by quit),
  /// `pauseModelDownload` (manually paused this session), and the internal failure
  /// paths (transient failures that exhausted retries).
  var pausedDownloads: [String: Int64] = [:]

  /// HF download context per model ID, gathered before download starts.
  /// Contains commit hash and blob hashes needed to write into HF cache layout.
  /// Nil for legacy flat-directory downloads (fallback when HF API calls fail).
  var downloadContexts: [String: HFDownloadCtx] = [:]

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

    // Rehydrate pending deeplink installs BEFORE refreshDownloadedModels so the
    // partial-scan allowlist sees their ids.
    hydratePendingInstalls()

    refreshDownloadedModels()
  }

  /// Downloads all required files for a model.
  /// Fetches HF metadata (commit hash, blob hashes) first, then starts URLSession tasks.
  func downloadModel(_ model: CatalogEntry) throws {
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
    let resumedBytes = pausedDownloads.removeValue(forKey: model.id) ?? 0

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
      let ctx = await self.fetchHFContext(for: model)
      await MainActor.run {
        guard let ctx else {
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
        self.downloadContexts[modelId] = ctx
        self.logger.info("HF context ready for \(model.displayName): \(ctx.repoDir)")
        self.startDownloadTasks(model: model, files: filesToDownload)
      }
    }
  }

  /// Starts URLSession data tasks for the given files.
  /// Each file streams into a `.partial` file under `<hf-cache>/.llamabarn-partial/<modelId>/`;
  /// if a partial already exists on disk, we resume via a `Range` header.
  private func startDownloadTasks(model: CatalogEntry, files: [URL]) {
    let modelId = model.id
    guard let ctx = downloadContexts[modelId] else {
      logger.error("Missing HF context when starting tasks for \(model.displayName)")
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
          modelId: modelId, cacheDir: cacheDir, url: fileUrl, ctx: ctx)
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
    modelId: String, cacheDir: URL, url: URL, ctx: HFDownloadCtx
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
      expectedBlobHash: ctx.blobHashes[url]
    )
  }

  /// Fetches HF file metadata (commit hash, blob hashes) for a model via HEAD requests.
  /// Each HEAD request returns both X-Repo-Commit and X-Linked-Etag, so one request
  /// per file gives us everything we need. Returns nil on failure (caller aborts download).
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
    if let bytes = pausedDownloads[model.id] {
      return .paused(bytesOnDisk: bytes, totalBytes: model.fileSize)
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
    let modelId = model.id
    let cacheDir = UserSettings.hfCacheDirectory
    Task.detached {
      do {
        // Clean up any lingering partial files for this model.
        HFCache.removePartials(cacheDir: cacheDir, modelId: modelId)

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
              cacheDir: cacheDir,
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

      // Absolute paths for all entries — HF cache or legacy flat.
      // ResolvedPaths already holds absolute paths for both cases (see refreshDownloadedModels).
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
          entry.fitResidentBytes = cached.residentBytes
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

      // Scan `.llamabarn-partial/` for interrupted downloads from a previous session.
      // Done on the same detached task so we know exactly which ids are already
      // installed (stale partial dirs for installed models get cleaned here).
      let installedIds = Set(allDownloaded.map(\.id))
      // Pending deeplink installs are valid owners of `.partial` directories
      // too — without them in `knownIds`, `scanPartials` would skip their
      // bytes-on-disk after a mid-download relaunch.
      let pendingIds = await MainActor.run { Set(ModelManager.shared.pendingInstalls.keys) }
      let knownIds = Set(allCatalogModels.map(\.id)).union(pendingIds)
      let paused = HFCache.scanPartials(
        cacheDir: hfCacheDir, knownIds: knownIds, installedIds: installedIds)

      await MainActor.run {
        Self.updateDownloadedModels(
          allDownloaded, resolved: finalResolved, pending: pendingFitParams, paused: paused)
      }
    }
  }

  private static func updateDownloadedModels(
    _ models: [CatalogEntry],
    resolved: [String: ResolvedPaths],
    pending: [(id: String, path: String)] = [],
    paused: [String: Int64] = [:]
  ) {
    let manager = ModelManager.shared
    manager.downloadedModels = models.sorted(by: CatalogEntry.displayOrder(_:_:))
    manager.resolvedPaths = resolved
    // Refresh paused downloads from the partial-dir scan. Authoritative — callers
    // from refreshDownloadedModels always pass the latest scan (possibly empty).
    // Drop active ids: their `.partial` files are on disk but owned by the transfer,
    // and they'd otherwise coexist in both `activeDownloads` and `pausedDownloads`.
    let excluded = Set(manager.downloadedModels.map(\.id))
      .union(manager.activeDownloads.keys)
    manager.pausedDownloads = paused.filter { !excluded.contains($0.key) }

    // Drop pending-install entries that have landed as installed sideloaded
    // models. Identity matches because both paths derive `{org}/{repo}:{QUANT}`
    // the same way, so the same id that was registered on deeplink pickup is
    // what `scanForSideloaded` emits post-download.
    let installedIds = Set(manager.downloadedModels.map(\.id))
    for id in manager.pendingInstalls.keys where installedIds.contains(id) {
      manager.pendingInstalls.removeValue(forKey: id)
      PendingInstallStore.remove(modelId: id)
    }

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
            mgr.downloadedModels[idx].fitResidentBytes = resolved.residentBytes
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
  func cancelModelDownload(_ model: CatalogEntry) {
    tearDownActiveDownload(modelId: model.id, outcome: .discard)
  }

  /// Stops an in-flight download but keeps the `.partial` bytes on disk so the user
  /// can resume it later. The model reappears in the Installed section as paused.
  func pauseModelDownload(_ model: CatalogEntry) {
    guard activeDownloads[model.id] != nil else { return }
    tearDownActiveDownload(modelId: model.id, outcome: .pause)
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

  // MARK: - Pending Installs (deeplink)

  /// Registers a deeplink-originated install and kicks off the download.
  /// The placeholder `entry` is a sideloaded-style `CatalogEntry` whose id
  /// matches what `HFCache.buildSideloadedEntry` will emit once the files
  /// are on disk — so the row's identity survives the post-download handoff.
  func registerPendingInstall(entry: CatalogEntry, descriptor: PendingInstallDescriptor) {
    // Idempotent: a repeated deeplink for the same id is a no-op if we're
    // already tracking it (pending, downloading, or installed).
    if downloadedModels.contains(where: { $0.id == entry.id }) { return }
    if activeDownloads[entry.id] != nil { return }

    pendingInstalls[entry.id] = entry
    PendingInstallStore.upsert(descriptor)
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)

    do {
      try downloadModel(entry)
    } catch {
      // `downloadModel` can throw if preflight fails (e.g. disk space). Keep
      // the pending row around so the user can retry, but log.
      logger.error(
        "registerPendingInstall: download start failed: \(error.localizedDescription)")
    }
  }

  /// Removes a pending install and persists the change. Called on explicit
  /// cancel (red X) — completion-on-download cleanup lives in
  /// `updateDownloadedModels`.
  func discardPendingInstall(id: String) {
    pendingInstalls.removeValue(forKey: id)
    PendingInstallStore.remove(modelId: id)
  }

  /// Rehydrates `pendingInstalls` from disk at app launch:
  ///   1. Seeds a minimal placeholder `CatalogEntry` so the row shows up in
  ///      the menu immediately (no waiting on the network).
  ///   2. Kicks off an async re-resolve via `DeeplinkHandler` — on success
  ///      the placeholder is replaced with a real resolved entry and the
  ///      download resumes from any `.partial` bytes already on disk.
  ///   3. On re-resolve failure (offline, network error, repo gone), leaves
  ///      the placeholder in place and logs. The row will just sit there
  ///      until the user triggers the deeplink again.
  func hydratePendingInstalls() {
    let descriptors = PendingInstallStore.load()
    for descriptor in descriptors {
      guard pendingInstalls[descriptor.modelId] == nil else { continue }
      // `mainUrl: nil` produces a sentinel-URL placeholder — `downloadModel`
      // refuses to act on it, and the async re-resolve below swaps it for a
      // real entry before the user can click.
      pendingInstalls[descriptor.modelId] = CatalogEntry.sideloadPlaceholder(
        modelId: descriptor.modelId,
        repo: descriptor.repo,
        quant: descriptor.quant,
        mainUrl: nil,
        additionalParts: [],
        mmprojUrl: nil,
        fileSize: 0)
    }

    // Kick off re-resolve AFTER seeding placeholders so the menu shows a row
    // immediately at launch even if the network is slow.
    for descriptor in descriptors {
      DeeplinkHandler.shared.rehydrate(descriptor: descriptor)
    }
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
    modelId: String, model: CatalogEntry,
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
    // We don't require exact size match — catalog sizes can drift when HF re-uploads.
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

    // Fetch HF ctx (commit/repoDir) on main actor.
    let ctx: HFDownloadCtx? = DispatchQueue.main.sync {
      self.downloadContexts[modelId]
    }
    guard let ctx else {
      handleDownloadFailure(
        modelId: modelId, model: model,
        reason: "Missing Hugging Face metadata for \(model.displayName).")
      return
    }
    let cacheDir = DispatchQueue.main.sync { UserSettings.hfCacheDirectory }

    do {
      try HFCache.writeBlobAndLink(
        cacheDir: cacheDir, repoDir: ctx.repoDir, commit: ctx.commit,
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
        self.downloadContexts.removeValue(forKey: modelId)
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
    modelId: String, model: CatalogEntry, reason: String
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
        "Hugging Face returned 404 for this file. The catalog URL may be out of date — please report this at https://github.com/ggml-org/LlamaBarn/issues."
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
      guard self.activeDownloads[modelId] != nil,
        let model = Catalog.findModel(id: modelId)
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
  private func restartTask(model: CatalogEntry, url: URL) {
    guard let ctx = downloadContexts[model.id] else { return }
    let cacheDir = UserSettings.hfCacheDirectory
    do {
      let writer = try openPartialWriter(
        modelId: model.id, cacheDir: cacheDir, url: url, ctx: ctx)
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
      downloadContexts.removeValue(forKey: modelId)
      // Clear retry counters — a subsequent resume/retry should start a fresh budget.
      if let model {
        for url in model.allDownloadUrls { clearRetryState(for: url) }
      }
    }

    switch outcome {
    case .discard:
      pausedDownloads.removeValue(forKey: modelId)
      HFCache.removePartials(cacheDir: UserSettings.hfCacheDirectory, modelId: modelId)
      // Deeplink-originated pending installs don't have a catalog fallback —
      // discarding means the row should disappear entirely, not revert to an
      // "available" catalog entry. Same-identity sideloaded entries get
      // rebuilt by `scanForSideloaded` if the user re-downloads.
      if pendingInstalls.removeValue(forKey: modelId) != nil {
        PendingInstallStore.remove(modelId: modelId)
      }
    case .pause:
      let bytes = HFCache.partialBytes(
        cacheDir: UserSettings.hfCacheDirectory, modelId: modelId)
      if bytes > 0 {
        pausedDownloads[modelId] = bytes
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
