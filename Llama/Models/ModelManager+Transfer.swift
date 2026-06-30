import Foundation
import Sentry
import os.log

/// The transfer engine behind `ModelManager.downloadModel`: URLSession delegate
/// callbacks that stream bytes into `.partial` files, finalization (hash
/// verification + promotion into the HF cache), failure reporting, and retry
/// with exponential backoff.
///
/// The delegate methods are nonisolated — they run on the session's background
/// queue and only hop to the main actor via fire-and-forget dispatch. Each
/// task's `PartialWriter` carries the context they need (model, cache dir,
/// plan), so they never reach back into main-actor state synchronously.
extension ModelManager {
  // MARK: - URLSessionDataDelegate

  nonisolated func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    // The writer carries everything we need (model, cache dir, plan), so the
    // delegate never reaches back into the main actor. The writer is registered
    // before the task is resumed, so it's always present by the first response.
    let taskId = dataTask.taskIdentifier
    guard let writer = writerTable.sync({ $0[taskId] }),
      let http = response as? HTTPURLResponse
    else {
      completionHandler(.cancel)
      return
    }
    let modelId = writer.modelId

    let status = http.statusCode

    // 416 Range Not Satisfiable — partial is already at or past the remote's size.
    // Short-circuit: cancel the transfer (no body needed) and finalize what's on disk.
    if status == 416 {
      writerTable.sync { $0[taskId] = nil }
      completionHandler(.cancel)
      logger.info("416 for \(writer.filename); partial appears complete, finalizing")
      finalizeTask(writer: writer, dataTask: dataTask)
      return
    }

    // Non-success statuses: fail the download with a user-facing message.
    if !(200...299).contains(status) {
      let message = userMessage(forHTTPStatus: status)
      // 401/403/404 are permanent — remove partials so a later retry doesn't replay a bad state.
      if [401, 403, 404].contains(status) {
        HFCache.removePartials(cacheDir: writer.cacheDir, modelId: modelId)
      }
      writerTable.sync { $0[taskId] = nil }
      writer.closeHandle()

      // Keep Sentry error-grouping stable across releases.
      let nsErr = NSError(
        domain: "Llama.ModelManager", code: status,
        userInfo: [
          NSLocalizedDescriptionKey: "Download failed with HTTP \(status)",
          "modelId": modelId,
          "url": dataTask.originalRequest?.url?.absoluteString ?? "unknown",
        ])
      SentrySDK.capture(error: nsErr)
      completionHandler(.cancel)
      handleDownloadFailure(model: writer.model, reason: message)
      return
    }

    // 200 OK — server ignored our Range request (or we didn't send one).
    // Restart the file: truncate, reset the running hash, reset byte counter.
    // Both 200 and 206 yield a full-size; stash it for progress tracking.
    let fullSize = extractFullSize(from: http)
    writerTable.sync { _ in
      if status == 200 {
        if writer.bytesWritten > 0 {
          logger.warning(
            "Server ignored Range for \(writer.filename); restarting from byte 0")
        }
        try? writer.handle.truncate(atOffset: 0)
        try? writer.handle.seek(toOffset: 0)
        writer.bytesWritten = 0
        writer.hasher = HFCache.SHA256Hasher()
      }
      if fullSize > 0 {
        writer.totalExpected = fullSize
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
    let taskId = dataTask.taskIdentifier
    let writeFailed = writerTable.sync { writers -> Bool in
      guard let writer = writers[taskId] else { return false }
      do {
        try writer.handle.write(contentsOf: data)
        writer.hasher.update(data)
        writer.bytesWritten += Int64(data.count)
        return false
      } catch {
        logger.error(
          "Write failed for \(writer.filename): \(error.localizedDescription)")
        return true
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
    guard let dataTask = task as? URLSessionDataTask else { return }
    let taskId = task.taskIdentifier

    // Always drop the writer so its file handle is closed before anything else
    // touches the file. Its `model` is our source of truth for reporting.
    let writer = writerTable.sync { $0.removeValue(forKey: taskId) }

    if let error {
      let nsError = error as NSError
      writer?.closeHandle()

      // Cancelled: either user cancel or our own short-circuit (416 / HTTP error already handled).
      // In both cases we've already done the cleanup or it doesn't apply.
      if nsError.code == NSURLErrorCancelled {
        return
      }

      // Capture remaining errors to Sentry; the SDK config in LlamaApp filters common noise.
      SentrySDK.capture(error: error)

      // No writer means a terminal handler already ran for this task; nothing to report.
      guard let writer else { return }
      let modelId = writer.modelId
      let model = writer.model
      let originalURL = task.originalRequest?.url

      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.logger.error("Model download failed: \(error.localizedDescription)")

        // Retry transient network errors (partial file is the resume state).
        if let originalURL, self.shouldRetry(error: nsError, url: originalURL) {
          self.scheduleRetry(url: originalURL, modelId: modelId)
          return
        }

        if self.activeDownloads[modelId] != nil {
          _ = self.updateActiveDownload(modelId: modelId) { agg in
            agg.removeTask(with: taskId)
          }
          self.refreshProgress(modelId: modelId)
          self.postDownloadsDidChange()
          NotificationCenter.default.post(
            name: .LBModelDownloadDidFail, object: self,
            userInfo: ["model": model, "error": error.localizedDescription]
          )
        }

        // Clear retry state on final failure.
        if let originalURL {
          self.clearRetryState(for: originalURL)
        }
      }
      return
    }

    // Success: promote the `.partial` into the HF cache.
    guard let writer else { return }  // already handled (e.g. 416 path)
    finalizeTask(writer: writer, dataTask: dataTask)
  }

  /// Hashes, verifies, and promotes a completed `.partial` file into `blobs/<sha256>`.
  /// Runs on the delegate queue (background). Never on the main queue — we do file I/O here.
  nonisolated private func finalizeTask(
    writer: PartialWriter, dataTask: URLSessionDataTask
  ) {
    writer.closeHandle()

    let model = writer.model
    let cacheDir = writer.cacheDir
    let plan = writer.plan
    let modelId = writer.modelId

    let fileSize = FileManager.default.fileSize(atPath: writer.partialURL.path)

    // Sanity check: reject obviously broken downloads (error pages, empty files).
    // We don't require an exact size match — expected sizes can drift when HF re-uploads.
    let minThreshold: Int64 = 1_000_000
    if fileSize <= minThreshold {
      try? FileManager.default.removeItem(at: writer.partialURL)
      handleDownloadFailure(model: model, reason: "file too small (\(fileSize) B)")
      return
    }

    // Digest from the running hasher (covers existing-prefix re-hash at open time, plus streamed bytes).
    let computed = writer.hasher.finalize()
    if let expected = writer.expectedBlobHash, expected != computed {
      logger.error(
        "Hash mismatch for \(writer.filename): expected \(expected), got \(computed)")
      try? FileManager.default.removeItem(at: writer.partialURL)
      handleDownloadFailure(
        model: model,
        reason: "File verification failed — the partial download was corrupt. Try again."
      )
      return
    }
    let blobHash = writer.expectedBlobHash ?? computed

    do {
      try HFCache.writeBlobAndLink(
        cacheDir: cacheDir, repoDir: plan.repoDir, commit: plan.commit,
        blobHash: blobHash, filename: writer.filename,
        from: writer.partialURL)
    } catch {
      logger.error(
        "Failed to promote partial \(writer.filename): \(error.localizedDescription)")
      handleDownloadFailure(model: model, reason: error.localizedDescription)
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
        // The plan rode along inside the ActiveDownload entry, which
        // updateActiveDownload already removed once the last task finished.
        // Clean up the now-empty partial dir (the file itself moved to blobs).
        HFCache.removePartials(cacheDir: cacheDir, modelId: modelId)
        self.refreshDownloadedModels()
      } else {
        self.refreshProgress(modelId: modelId)
      }
      self.postDownloadsDidChange()
    }
  }

  /// Delegate-queue entry point for failures: hops to the main actor and funnels
  /// into `failDownload`, the single failure-reporting path.
  nonisolated private func handleDownloadFailure(model: Model, reason: String) {
    DispatchQueue.main.async { [weak self] in
      self?.failDownload(model: model, reason: reason)
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
  nonisolated private func extractFullSize(from response: HTTPURLResponse) -> Int64 {
    if response.statusCode == 206,
      let cr = response.value(forHTTPHeaderField: "Content-Range")
    {
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
        self.clearRetryState(for: url)
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
    guard let plan = activeDownloads[model.id]?.plan else { return }
    let cacheDir = UserSettings.hfCacheDirectory
    // Re-open the writer off the main actor — like the initial start, this
    // re-hashes the on-disk prefix and must not block the UI. The `Task`
    // inherits the main actor, so we resume on it after the `await`.
    Task {
      let writer: PartialWriter
      do {
        writer = try await openPartialWriter(
          model: model, cacheDir: cacheDir, url: url, plan: plan)
      } catch {
        logger.error(
          "Retry failed to open partial for \(url.lastPathComponent): \(error.localizedDescription)"
        )
        handleDownloadFailure(
          model: model,
          reason: "Couldn't reopen staging file for retry: \(error.localizedDescription)"
        )
        return
      }
      // Register and start the task (no-op if cancelled during the re-hash).
      startWriterTask(writer, modelId: model.id)
    }
  }

  /// Clears retry state for a URL (called on success or user cancellation).
  func clearRetryState(for url: URL) {
    retryAttempts.removeValue(forKey: url)
  }

}
