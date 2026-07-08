import Foundation
import Network
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

  /// Model id → paused-download state (bytes on disk + the `Model` the row
  /// will render from). Sources: `pauseModelDownload` (manually paused this
  /// session) and the internal failure paths (transient failures that
  /// exhausted retries). Carrying the entry here means paused deeplinks
  /// survive teardown without a separate placeholder registry.
  /// Rehydrated across restarts from the on-disk `.model.json` placeholder each
  /// download writes (see `persistPlaceholder` / `HFCache.scanPlaceholders`), so
  /// an interrupted download reappears as a paused row rather than vanishing.
  var pausedDownloads: [String: PausedDownload] = [:]

  /// Per-task streaming state for in-flight downloads, keyed by
  /// `URLSessionTask.taskIdentifier`. Accessed from both the URLSession delegate
  /// queue (nonisolated) and the main actor; the table serializes all access.
  nonisolated let writerTable = WriterTable()

  // Retry state: tracks attempt count per URL for exponential backoff
  var retryAttempts: [URL: Int] = [:]
  let maxRetryAttempts = 3
  let baseRetryDelay: TimeInterval = 2.0  // Doubles each attempt: 2s, 4s, 8s

  // Connectivity gating. The backoff timer alone can't recover from a wake-from-sleep:
  // wifi reassociation after wake takes longer than the 2s/4s/8s budget, so a blind
  // timer burns all three attempts during the window where no path exists and fails
  // the download outright. Instead we watch the network path — when a transient error
  // lands while offline we don't consume an attempt; we park the download as a paused
  // row and auto-resume it once the path is restored.
  private let pathMonitor = NWPathMonitor()
  /// Latest network-path status from `pathMonitor`. Optimistically `true` until the
  /// monitor delivers its first update, so a download started before then isn't
  /// wrongly treated as offline.
  var isNetworkAvailable = true
  /// Model ids we paused because the network path went away mid-download. These
  /// auto-resume on the next offline→online path edge; user-initiated pauses are
  /// deliberately absent so they stay paused.
  var downloadsPausedForConnectivity: Set<String> = []

  private var urlSession: URLSession!
  let logger = Logger(subsystem: Logging.subsystem, category: "ModelManager")

  // Throttle progress notifications to prevent excessive UI refreshes.
  var lastNotificationTime: [String: Date] = [:]
  let notificationThrottleInterval: TimeInterval = 0.1

  override init() {
    super.init()

    // URLSession delegate callbacks run on a background queue to avoid blocking the main thread
    // during file operations. The callbacks are self-contained — each writer carries the context
    // it needs (model, cache dir, plan) — so they never hop back to the main actor synchronously;
    // they only fire-and-forget `DispatchQueue.main.async` for UI/state updates. Shared writer
    // state lives in `writerTable`, which serializes access on its own queue.
    let queue = OperationQueue()
    queue.qualityOfService = .userInitiated

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 120  // Temporary network stalls
    config.timeoutIntervalForResource = 60 * 60 * 24  // 24 hours for large files

    urlSession = URLSession(configuration: config, delegate: self, delegateQueue: queue)

    // Watch the network path so connectivity-paused downloads can auto-resume when
    // the path is restored (e.g. after wake-from-sleep, once wifi reassociates).
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let satisfied = path.status == .satisfied
      DispatchQueue.main.async {
        self?.handlePathUpdate(satisfied: satisfied)
      }
    }
    pathMonitor.start(queue: DispatchQueue.global(qos: .utility))

    refreshDownloadedModels()
  }

  /// Reacts to a network-path change. On the offline→online edge, resumes any
  /// downloads we parked for connectivity. Ignores every other transition (staying
  /// online, going offline, interface swaps) so we only ever kick resumes off a
  /// genuine restoration.
  private func handlePathUpdate(satisfied: Bool) {
    let wasAvailable = isNetworkAvailable
    isNetworkAvailable = satisfied
    guard satisfied, !wasAvailable, !downloadsPausedForConnectivity.isEmpty else { return }

    logger.info(
      "Network path restored; resuming \(self.downloadsPausedForConnectivity.count) connectivity-paused download(s)"
    )
    // downloadModel (and the guard below) mutate the set, so iterate a snapshot;
    // drop any id that's no longer paused (user discarded/resumed in the meantime).
    for modelId in Array(downloadsPausedForConnectivity) {
      guard let model = pausedDownloads[modelId]?.model else {
        downloadsPausedForConnectivity.remove(modelId)
        continue
      }
      do {
        try downloadModel(model)
      } catch {
        logger.error(
          "Auto-resume failed for \(model.displayName): \(error.localizedDescription)")
        downloadsPausedForConnectivity.remove(modelId)
      }
    }
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
    // Starting (or resuming) supersedes any connectivity-park state for this model;
    // if it fails again offline the transient path re-registers it.
    downloadsPausedForConnectivity.remove(model.id)

    let filesToDownload = try prepareDownload(for: model)
    guard !filesToDownload.isEmpty else { return }

    logger.info("Starting download for model: \(model.displayName)")

    // Persist a placeholder so an interrupted download (app quit/crash/update
    // mid-transfer) reappears as a paused row on next launch instead of
    // silently vanishing. The `.partial` bytes already survive; this just keeps
    // the `Model` needed to render and resume the row without a network resolve.
    persistPlaceholder(for: model)

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
          self.failDownload(
            model: model,
            reason:
              "Couldn't reach Hugging Face to start the download. This is usually a temporary rate limit or outage — try again in a few minutes, or set a Hugging Face token in Settings to lift the limit."
          )
          return
        }
        // The placeholder entry may be gone if the user cancelled during the
        // async metadata fetch; if so, this is a no-op and startDownloadTasks
        // bails on the missing plan below.
        self.activeDownloads[modelId]?.plan = plan
        self.logger.info("HF download plan ready for \(model.displayName): \(plan.repoDir)")
        self.startDownloadTasks(model: model, files: filesToDownload)
      }
    }
  }

  /// Writes the model's placeholder JSON into its partial dir so the paused row
  /// can be rebuilt at launch. Best-effort: a failure only means the download
  /// won't reappear after a restart (re-clicking still resumes), so it's logged,
  /// not surfaced. The placeholder dies with the partial dir on completion/cancel.
  private func persistPlaceholder(for model: Model) {
    let url = HFCache.placeholderURL(cacheDir: UserSettings.hfCacheDirectory, modelId: model.id)
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(model).write(to: url, options: .atomic)
    } catch {
      logger.error(
        "Failed to write download placeholder for \(model.displayName): \(error.localizedDescription)"
      )
    }
  }

  /// Starts URLSession data tasks for the given files.
  /// Each file streams into a `.partial` file under `<hf-cache>/.llama-partial/<modelId>/`;
  /// if a partial already exists on disk, we resume via a `Range` header.
  private func startDownloadTasks(model: Model, files: [URL]) {
    let modelId = model.id
    // Reuse the placeholder entry `downloadModel` registered — it already carries
    // the plan and the resumed-bytes-seeded progress, so the row never flashes
    // back to 0% while the tasks spin up.
    guard let plan = activeDownloads[modelId]?.plan else {
      logger.error("Missing HF download plan when starting tasks for \(model.displayName)")
      tearDownActiveDownload(modelId: modelId, outcome: .pause)
      return
    }
    let cacheDir = UserSettings.hfCacheDirectory

    // Open every `.partial` writer off the main actor (each re-hashes its on-disk
    // prefix — potentially many GB on a resume), then hop back here to register
    // the tasks and start them. The `Task` inherits the main actor, so the body
    // resumes on it after each `await`.
    Task {
      var writers: [PartialWriter] = []
      do {
        for fileUrl in files {
          writers.append(
            try await openPartialWriter(model: model, cacheDir: cacheDir, url: fileUrl, plan: plan))
        }
      } catch {
        // Couldn't open/rehash one of the partials — abort the whole model
        // download and close any handles we did open so we don't leak them.
        for writer in writers { writer.closeHandle() }
        failDownload(
          model: model,
          reason: "Couldn't open staging file: \(error.localizedDescription)")
        return
      }

      // Register and start each task. `startWriterTask` skips (and closes) any
      // writer whose download was cancelled/paused while we were hashing.
      for writer in writers { startWriterTask(writer, modelId: modelId) }
      refreshProgress(modelId: modelId)
      postDownloadsDidChange()
    }
  }

  /// Registers an opened writer's data task with the transfer machinery and starts it.
  /// No-op (closing the writer's handle) if the download was cancelled while the writer
  /// was being opened off the main actor. Main-actor only.
  func startWriterTask(_ writer: PartialWriter, modelId: String) {
    guard activeDownloads[modelId] != nil else {
      writer.closeHandle()
      return
    }
    let task = makeDataTask(for: writer.url, modelId: modelId, writer: writer)
    writerTable.sync { $0[task.taskIdentifier] = writer }
    _ = updateActiveDownload(modelId: modelId) { $0.addTask(task) }
    task.resume()
  }

  /// Builds a URLSessionDataTask for a remote file. Adds a `Range: bytes=N-` header when
  /// the writer's on-disk `.partial` already has N bytes.
  func makeDataTask(
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
  /// hash over any already-present prefix. `nonisolated async` so the re-hash runs off the
  /// main actor: on a resumed download the existing prefix can be many GB, and hashing it
  /// synchronously on the main actor freezes the UI (spinning-wait cursor) until it finishes.
  nonisolated func openPartialWriter(
    model: Model, cacheDir: URL, url: URL, plan: HFDownloadPlan
  ) async throws -> PartialWriter {
    let modelId = model.id
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
      existing = FileManager.default.fileSize(atPath: partialURL.path)
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
      model: model, cacheDir: cacheDir, plan: plan,
      url: url, filename: filename,
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
    let blobHashes = allMetadata.compactMapValues(\.blobHash)

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

    // If the model being deleted is the active one, the server restart triggered
    // below (via reload() once models.ini changes) drops it; status polling then
    // reconciles modelStatuses, clearing the derived activeModelId.

    let paths = resolvedPaths[model.id]

    // Optimistically update state immediately for responsive UI
    downloadedModels.removeAll { $0.id == model.id }
    resolvedPaths.removeValue(forKey: model.id)
    syncServer()
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)

    // Move file deletion to background queue to avoid blocking main thread
    let modelId = model.id
    let cacheDir = UserSettings.hfCacheDirectory
    Task.detached { [weak self] in
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
        guard let self else { return }
        await MainActor.run {
          self.restoreDeletedModel(model, error: error)
        }
      }
    }
  }

  private func restoreDeletedModel(_ model: Model, error: Error) {
    downloadedModels.append(model)
    downloadedModels.sort(by: Model.displayOrder(_:_:))
    // Re-scan to rebuild resolvedPaths
    refreshDownloadedModels()
    logger.error("Failed to delete model: \(error.localizedDescription)")
  }

  /// Regenerates `models.ini` and restarts the server only when the content
  /// actually changed — the single "model list changed, tell the server" path.
  func syncServer() {
    if updateModelsFile() {
      LlamaServer.shared.reload()
    }
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

    // Enable larger batch size for better performance on high-memory devices (>=32 GB RAM)
    let useLargeBatch = Double(SystemMemory.memoryMb) / 1024.0 >= 32.0

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

      // Wire up MTP speculative decoding -- a free speedup on the MoE builds
      // (Qwen3.6 etc.) that ship a multi-token-prediction head. Two shapes:
      // a separate `mtp-….gguf` sidecar (passed as the draft model), or a head
      // embedded in the main weights (reused via its own MTP context, no draft
      // file). Sidecar wins when both look present.
      if let mtpSidecar = paths.mtpSidecarFile {
        content += "spec-type = draft-mtp\n"
        content += "spec-draft-model = \(mtpSidecar)\n"
      } else if paths.usesMTP {
        content += "spec-type = draft-mtp\n"
      }
      // Cap drafted tokens per step at 3 for MTP -- the value Georgi Gerganov
      // recommended; MTP heads only predict a few tokens ahead reliably, so
      // drafting deeper just wastes compute on tokens the target rejects.
      if paths.mtpSidecarFile != nil || paths.usesMTP {
        content += "spec-draft-n-max = 3\n"
      }

      if useLargeBatch {
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
    #if DEBUG
      // DEBUG fixture: replace the real cache scan with a large, realistic list
      // so the long-list UI can be worked on without downloading any weights.
      // Skips mem-profiling, models.ini, and the server reload entirely.
      if SimulatedModels.isEnabled {
        downloadedModels = SimulatedModels.all.sorted(by: Model.displayOrder(_:_:))
        resolvedPaths = [:]
        NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
        return
      }
    #endif

    let hfCacheDir = UserSettings.hfCacheDirectory

    // Move directory reading to background queue to avoid blocking main thread
    Task.detached { [weak self] in
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

      // Rehydrate paused rows for downloads interrupted in a previous session:
      // decode each on-disk placeholder back into a `Model` and pair it with its
      // current bytes-on-disk. No network resolve needed — the placeholder
      // carries the full `Model`.
      let pausedEntries = HFCache.scanPlaceholders(cacheDir: hfCacheDir).compactMap {
        url -> (model: Model, bytesOnDisk: Int64)? in
        guard let data = try? Data(contentsOf: url),
          let model = try? JSONDecoder().decode(Model.self, from: data)
        else { return nil }
        return (model, HFCache.partialBytes(cacheDir: hfCacheDir, modelId: model.id))
      }

      let allDownloaded = models
      let finalResolved = resolvedPaths
      let pendingProfile = needsProfile

      guard let self else { return }
      await MainActor.run {
        self.updateDownloadedModels(
          allDownloaded, resolved: finalResolved, pending: pendingProfile, paused: pausedEntries)
      }
    }
  }

  private func updateDownloadedModels(
    _ models: [Model],
    resolved: [String: ResolvedPaths],
    pending: [(id: String, path: String)] = [],
    paused: [(model: Model, bytesOnDisk: Int64)] = []
  ) {
    downloadedModels = models.sorted(by: Model.displayOrder(_:_:))
    resolvedPaths = resolved
    // Drop paused entries that are now installed or actively downloading, then
    // fold in the rehydrated on-disk placeholders. The merge is idempotent: a
    // download paused this session has both an in-memory entry and a placeholder
    // carrying the same `Model`, and an active download's id is excluded below.
    let excluded = Set(downloadedModels.map(\.id))
      .union(activeDownloads.keys)
    pausedDownloads = pausedDownloads.filter { !excluded.contains($0.key) }
    for entry in paused where !excluded.contains(entry.model.id) {
      pausedDownloads[entry.model.id] = PausedDownload(
        model: entry.model, bytesOnDisk: entry.bytesOnDisk)
    }

    // Only reload server if models.ini actually changed
    syncServer()

    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)

    // Kick off async mem-profile probing for models without cached results
    if !pending.isEmpty {
      enrichWithMemProfiles(pending)
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
        // llama fit-params can't dyld-link) would otherwise stick across
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
          mgr.syncServer()

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
    writerTable.sync { writers in
      for id in taskIds {
        writers.removeValue(forKey: id)?.closeHandle()
      }
    }
  }

  /// Updates an active download by applying a modification and removing it if empty.
  /// Returns true if the download was removed (completed or cancelled), false if still in progress.
  func updateActiveDownload(
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
  enum TeardownOutcome {
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
  func tearDownActiveDownload(modelId: String, outcome: TeardownOutcome) {
    let model = activeDownloads[modelId]?.model

    // Any teardown clears connectivity-park state; the transient path re-inserts
    // afterward for the offline case, so user pause/discard here stays paused.
    downloadsPausedForConnectivity.remove(modelId)

    if activeDownloads[modelId] != nil {
      cancelTasks(for: modelId)
      activeDownloads.removeValue(forKey: modelId)
      lastNotificationTime.removeValue(forKey: modelId)
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

  /// Single failure-reporting path: tears down the download (keeping partials so
  /// the row resurfaces as paused where possible) and posts the failure alert.
  /// Used both by start-time failures here and by the transfer engine's
  /// delegate-queue failure handler (via a main-actor hop).
  func failDownload(model: Model, reason: String) {
    logger.error("Model download failed (\(reason)) for model: \(model.displayName)")
    tearDownActiveDownload(modelId: model.id, outcome: .pause)
    NotificationCenter.default.post(
      name: .LBModelDownloadDidFail,
      object: self,
      userInfo: ["model": model, "error": reason]
    )
  }

  /// Recomputes the aggregate progress for a model from its per-task writer state.
  /// Safe to call from the main actor at any time.
  func refreshProgress(modelId: String) {
    guard var download = activeDownloads[modelId] else { return }
    let taskIds = Array(download.tasks.keys)
    let (active, expected) = writerTable.sync { writers -> (Int64, Int64) in
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
    if let mtpUrl = model.mtpUrl, !hfFileExists(model: model, url: mtpUrl) {
      files.append(mtpUrl)
    }

    return files
  }

  /// Checks if a file exists in the HF cache for a given model and remote URL.
  private func hfFileExists(model: Model, url: URL) -> Bool {
    guard let repoDir = model.hfRepoDir else { return false }
    let filename = HFCache.repoRelativePath(from: url) ?? url.lastPathComponent
    return HFCache.snapshotFileExists(
      cacheDir: UserSettings.hfCacheDirectory, repoDir: repoDir, filename: filename)
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
      sum + FileManager.default.fileSize(atPath: path)
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

  func postDownloadsDidChange() {
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }
}
