import CryptoKit
import Foundation
import Sentry
import os.log

/// The transfer engine behind `ModelManager.downloadModel`: URLSession delegate
/// callbacks that stream each file's segments into its `.partial`, finalization
/// (hash verification + promotion into the HF cache), failure reporting, and
/// retry with exponential backoff.
///
/// The delegate methods are nonisolated — they run on the sessions' shared
/// background queue and only hop to the main actor via fire-and-forget
/// dispatch. Each request's `SegmentTask` entry leads to its file's
/// `PartialWriter`, which carries the context they need (model, cache dir,
/// plan), so they never reach back into main-actor state synchronously.
extension ModelManager {
  // MARK: - URLSessionDataDelegate

  nonisolated func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    // The writer carries everything we need (model, cache dir, plan), so the
    // delegate never reaches back into the main actor. The entry is registered
    // before the task is resumed, so it's present by the first response unless
    // a teardown already dropped it.
    let key = ObjectIdentifier(dataTask)
    guard let writer = writerTable.sync({ $0[key]?.writer }),
      let http = response as? HTTPURLResponse
    else {
      completionHandler(.cancel)
      return
    }

    // Every request asks for a range, so 206 Partial Content is the one success.
    let status = http.statusCode
    if status == 206 {
      completionHandler(.allow)
      return
    }

    writerTable.sync { $0[key] = nil }
    completionHandler(.cancel)

    let message: String
    if status == 200 {
      // The server ignored the Range header and is sending the whole file,
      // which a segment can't take. HF's CDN honors ranges, so this would take
      // something in between (a proxy) -- reported to Sentry with the HTTP
      // errors below, so it shows up if it ever happens.
      message = "Download failed: the server ignored a request for part of the file (HTTP 200)."
    } else {
      message = userMessage(forHTTPStatus: status)
      // 401/403/404 are permanent — remove partials so a later retry doesn't replay a bad state.
      if [401, 403, 404].contains(status) {
        HFCache.removePartials(cacheDir: writer.cacheDir, modelId: writer.modelId)
      }
    }

    // Keep Sentry error-grouping stable across releases.
    let nsErr = NSError(
      domain: "Llama.ModelManager", code: status,
      userInfo: [
        NSLocalizedDescriptionKey: "Download failed with HTTP \(status)",
        "modelId": writer.modelId,
        "url": dataTask.originalRequest?.url?.absoluteString ?? "unknown",
      ])
    handleDownloadFailure(model: writer.model, reason: message, error: nsErr)
  }

  nonisolated func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
  ) {
    let key = ObjectIdentifier(dataTask)
    let failure = writerTable.sync { entries -> (writer: PartialWriter, error: Error)? in
      guard let entry = entries[key] else { return nil }
      do {
        try entry.writer.write(data, segment: entry.index)
        return nil
      } catch {
        entries[key] = nil
        return (entry.writer, error)
      }
    }
    if let failure {
      // Typically a full disk, which no segment gets past -- fail the download.
      dataTask.cancel()
      logger.error(
        "Write failed for \(failure.writer.filename): \(failure.error.localizedDescription)")
      handleDownloadFailure(
        model: failure.writer.model,
        reason: "Couldn't save \(failure.writer.filename): \(failure.error.localizedDescription)")
      return
    }

    guard let modelId = dataTask.taskDescription else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, var download = self.activeDownloads[modelId] else { return }
      let now = Date()
      if now.timeIntervalSince(download.lastNotified) >= self.notificationThrottleInterval {
        download.lastNotified = now
        self.activeDownloads[modelId] = download
        self.refreshProgress(modelId: modelId)
        self.postDownloadsDidChange()
      }
    }
  }

  nonisolated func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    // Always drop the entry, so nothing more is written for this request. Its
    // writer is our source of truth for reporting.
    let key = ObjectIdentifier(task)
    let finished = writerTable.sync { entries -> (entry: SegmentTask, segmentDone: Bool)? in
      guard let entry = entries.removeValue(forKey: key) else { return nil }
      return (entry, entry.writer.state.segments[entry.index].isDone)
    }

    // Cancelled: either a teardown or our own short-circuit (HTTP error or
    // failed write, already handled). Either way there's nothing to do.
    if let error, (error as NSError).code == NSURLErrorCancelled { return }

    // No entry means a terminal handler already ran for this task; nothing to report.
    guard let (entry, segmentDone) = finished else { return }
    let writer = entry.writer
    let modelId = writer.modelId

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      // Only while this file is still part of the live download. A sibling's
      // failure may have torn the download down already (transient failures
      // can park it, then cancel the others — those arrive here as
      // NSURLErrorCancelled and returned early above, but guard anyway so a
      // late straggler doesn't resurrect state), and a resume since would have
      // its own writer for the file.
      guard self.activeDownloads[modelId]?.writers[writer.url] === writer else { return }

      // This request is over either way; a retry gets a task of its own.
      self.activeDownloads[modelId]?.removeTask(key)

      if let error {
        // Captured here, behind the guard above, so a failure that hits every
        // segment at once is reported once. The SDK config in LlamaApp
        // filters common noise.
        SentrySDK.capture(error: error)
        self.logger.error("Model download failed: \(error.localizedDescription)")

        // Transient network errors (timeout, connection lost, offline) are
        // resumable — the segment's bytes on disk are our resume state. Handle
        // them inline (retry or park as a paused row) rather than popping a modal.
        if self.isTransientNetworkError(error as NSError) {
          self.handleTransientFailure(writer: writer, segment: entry.index)
          return
        }

        // Anything else (bad cert, unsupported URL, ...) is genuinely actionable:
        // drop to a paused row and surface the failure alert.
        self.failDownload(model: writer.model, reason: error.localizedDescription)
        return
      }

      // The response ended before the segment's last byte, without an error:
      // fetch the rest, as after a dropped connection.
      guard segmentDone else {
        self.logger.warning("\(writer.filename) segment \(entry.index) ended early")
        self.handleTransientFailure(writer: writer, segment: entry.index)
        return
      }
      self.finalizeIfComplete(writer)
    }
  }

  // MARK: - Finalization

  /// Verifies a file and promotes it into the HF cache once all its segments
  /// are in and none is still running. Called whenever a segment finishes (or
  /// turns out to have nothing left to fetch); only the call that finds the
  /// file complete goes further, and only once.
  func finalizeIfComplete(_ writer: PartialWriter) {
    let claimed = writerTable.sync { entries -> Bool in
      guard !writer.isFinalizing, writer.state.isComplete,
        !entries.values.contains(where: { $0.writer === writer })
      else { return false }
      writer.isFinalizing = true
      // Nothing writes to the file any more: record it as complete (a pause
      // mid-verification then resumes straight into verification) and close it.
      writer.saveState()
      writer.closeHandle()
      return true
    }
    guard claimed else { return }

    // Show the file as complete (and the row as verifying, when it's the last
    // one) -- its last bytes may have landed after the last throttled refresh.
    refreshProgress(modelId: writer.modelId)
    postDownloadsDidChange()

    // Hash off the main actor -- seconds for a large file -- but promote back
    // on it, where pause and cancel run, so neither can slip in between the
    // check that the download still wants this file and the move into the cache.
    let partialURL = writer.partialURL
    Task.detached(priority: .userInitiated) { [weak self] in
      let digest = Result { () throws -> String in
        var hasher = SHA256()
        try HFCache.feedHasher(&hasher, from: partialURL)
        return HFCache.hex(hasher.finalize())
      }
      await self?.promote(writer, digest: digest)
    }
  }

  /// Second half of `finalizeIfComplete`, back on the main actor: checks the
  /// digest, moves the file into `blobs/<sha256>`, and completes the download
  /// when it was the last file.
  private func promote(_ writer: PartialWriter, digest: Result<String, Error>) {
    let modelId = writer.modelId
    let model = writer.model

    // Paused or cancelled while hashing: the teardown dropped the writer, and
    // the bytes either stay for a resume (which verifies them again) or went
    // with the partials.
    guard activeDownloads[modelId]?.writers[writer.url] === writer else { return }

    let computed: String
    switch digest {
    case .success(let hex):
      computed = hex
    case .failure(let error):
      failDownload(
        model: model,
        reason: "Couldn't read \(writer.filename) to verify it: \(error.localizedDescription)")
      return
    }
    if let expected = writer.expectedBlobHash, expected != computed {
      logger.error(
        "Hash mismatch for \(writer.filename): expected \(expected), got \(computed)")
      // The bytes go, and their state with them, so a retry fetches the file afresh.
      try? FileManager.default.removeItem(at: writer.partialURL)
      try? FileManager.default.removeItem(at: PartialState.url(for: writer.partialURL))
      failDownload(
        model: model,
        reason: "File verification failed — the partial download was corrupt. Try again."
      )
      return
    }
    let blobHash = writer.expectedBlobHash ?? computed

    let cacheDir = writer.cacheDir
    do {
      try HFCache.writeBlobAndLink(
        cacheDir: cacheDir, repoDir: writer.plan.repoDir, commit: writer.plan.commit,
        blobHash: blobHash, filename: writer.filename,
        from: writer.partialURL)
    } catch {
      logger.error(
        "Failed to promote partial \(writer.filename): \(error.localizedDescription)")
      failDownload(model: model, reason: error.localizedDescription)
      return
    }
    // The state goes with the bytes it described.
    try? FileManager.default.removeItem(at: PartialState.url(for: writer.partialURL))

    let fileSize = writerTable.sync { _ in writer.state.size }
    activeDownloads[modelId]?.writers[writer.url] = nil
    activeDownloads[modelId]?.completedFilesBytes += fileSize
    guard activeDownloads[modelId]?.writers.isEmpty == true else {
      refreshProgress(modelId: modelId)
      postDownloadsDidChange()
      return
    }

    activeDownloads.removeValue(forKey: modelId)
    logger.info("All downloads completed for model: \(model.displayName)")
    // Clean up the now-empty partial dir (the files themselves moved to blobs).
    HFCache.removePartials(cacheDir: cacheDir, modelId: modelId)
    // Optimistically mark the model installed before the async cache re-scan
    // lands. Without this, the model is neither downloading nor installed for
    // a beat, so its row hops back to the catalog list and then reappears.
    // The scan below replaces `downloadedModels` wholesale with the
    // authoritative on-disk entry, so no dedup is needed.
    if !downloadedModels.contains(where: { $0.id == modelId }) {
      downloadedModels.append(model)
      downloadedModels.sort(by: Model.displayOrder(_:_:))
    }
    refreshDownloadedModels()
    // Let the menu bar flag the finished download on its icon, in case the
    // user walked away during a long download and isn't watching the menu.
    NotificationCenter.default.post(name: .LBModelDownloadDidComplete, object: nil)
    postDownloadsDidChange()
  }

  /// Delegate-queue entry point for failures: hops to the main actor and funnels
  /// into `failDownload`, the single failure-reporting path. Only the first
  /// failure of a download gets through -- a cause that hits every segment
  /// (a 403, a full disk) would otherwise post an alert per segment -- and
  /// `error`, if given, goes to Sentry behind the same guard.
  nonisolated private func handleDownloadFailure(
    model: Model, reason: String, error: Error? = nil
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.activeDownloads[model.id] != nil else { return }
      if let error { SentrySDK.capture(error: error) }
      self.failDownload(model: model, reason: reason)
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
        "Hugging Face requires authentication for this download. Sign in to Hugging Face in Settings > Advanced and try again."
    case 403, 429:
      return
        "Hugging Face refused the download (HTTP \(status)). This usually means a rate limit — try again in a few minutes, or sign in to Hugging Face in Settings to lift the limit."
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

  // MARK: - Retry Logic

  /// URLSession error codes we treat as transient/resumable network failures, as
  /// opposed to actionable errors (bad certs, malformed URLs) that warrant an alert.
  private static let transientNetworkErrorCodes: Set<Int> = [
    NSURLErrorTimedOut,
    NSURLErrorNetworkConnectionLost,
    NSURLErrorNotConnectedToInternet,
    NSURLErrorCannotConnectToHost,
    NSURLErrorDNSLookupFailed,
  ]

  /// Whether an error is a transient, resumable network failure.
  func isTransientNetworkError(_ error: NSError) -> Bool {
    Self.transientNetworkErrorCodes.contains(error.code)
  }

  /// Handles a transient network failure for one segment within an active download.
  /// The decision hinges on connectivity so a wake-from-sleep recovers cleanly:
  /// - path up + attempts left: genuine blip, so back off and retry (keeps the
  ///   download live), consuming an attempt.
  /// - path down: don't consume an attempt (wifi may just be reassociating) — park
  ///   the whole model as a paused row and auto-resume when the path is restored.
  /// - attempts exhausted while online: the connection is genuinely troubled; park
  ///   as a paused row (no modal) the user can resume by hand, with a fresh budget.
  func handleTransientFailure(writer: PartialWriter, segment index: Int) {
    let model = writer.model
    let modelId = model.id
    let attempts = activeDownloads[modelId]?.retryAttempts[SegmentKey(url: writer.url, index: index)] ?? 0
    if isNetworkAvailable && attempts < maxRetryAttempts {
      scheduleRetry(index, of: writer)
      return
    }

    // Park as a paused row. tearDownActiveDownload cancels the model's other
    // tasks and (given partial bytes on disk) surfaces the paused row with its
    // existing resume affordance — no failure alert. When offline, the row is
    // flagged to auto-resume on the next path-restored edge.
    logger.info(
      "Parking \(model.displayName) as paused after transient failure (network \(self.isNetworkAvailable ? "up, attempts exhausted" : "down"))"
    )
    tearDownActiveDownload(
      modelId: modelId, outcome: .pause(resumeOnReconnect: !isNetworkAvailable))
  }

  /// Schedules a retry of one segment with exponential backoff. The writer is
  /// still open and the segment's bytes on disk are its resume state, so all a
  /// retry needs is a fresh range request.
  private func scheduleRetry(_ index: Int, of writer: PartialWriter) {
    let modelId = writer.modelId
    let key = SegmentKey(url: writer.url, index: index)
    let attempts = activeDownloads[modelId]?.retryAttempts[key] ?? 0
    activeDownloads[modelId]?.retryAttempts[key] = attempts + 1

    // Exponential backoff: 2s, 4s, 8s
    let delay = baseRetryDelay * pow(2.0, Double(attempts))

    logger.info(
      "Scheduling retry \(attempts + 1)/\(self.maxRetryAttempts) for \(writer.filename) segment \(index) in \(delay)s"
    )

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      self?.restartSegment(index, of: writer)
    }
  }

  /// Restarts one segment of an active download (used by retries). Goes
  /// through the writer the failed request used, not a lookup by URL: if the
  /// download was paused and resumed during the backoff, the resume started
  /// this segment already, under a writer of its own, and `startSegment` skips
  /// a writer that's no longer the live one -- rather than run the segment twice.
  private func restartSegment(_ index: Int, of writer: PartialWriter) {
    // Cancelled or paused meanwhile -- teardown removed the entry, retry
    // counters and all. (`startSegment` checks again after the token refresh.)
    guard activeDownloads[writer.modelId]?.writers[writer.url] === writer else { return }
    // The `Task` inherits the main actor, so `startSegment` runs on it.
    Task {
      // A retry can come hours into a long download, past the signed-in
      // token's expiry -- renew it before `startSegment` reads it.
      await HFAuth.refreshIfNeeded()
      logger.info("Retrying \(writer.filename) segment \(index)")
      startSegment(index, of: writer)
    }
  }
}
