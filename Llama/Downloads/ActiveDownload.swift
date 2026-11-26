import Foundation

/// Paused download state. Carries the `Model` so deeplink-sideload
/// placeholders can still render a paused row after their active download
/// is torn down.
struct PausedDownload {
  let model: Model
  let bytesOnDisk: Int64
  /// True when the pause was forced by the network path dropping mid-download;
  /// such entries auto-resume on the next offline→online edge (`handlePathUpdate`).
  /// User-initiated pauses keep this false so they stay paused. In-memory only —
  /// a restart rehydrates paused rows from placeholders with the flag off.
  var resumeOnReconnect = false
}

/// Tracks the progress of a multi-file model download.
///
/// Bytes-in-flight are tracked externally (each file's `PartialWriter` counts
/// its segments' bytes, since we stream into `.partial` files ourselves rather
/// than relying on URLSession's `countOfBytesReceived`). The caller passes
/// current sums into `refreshProgress`.
struct ActiveDownload {
  let model: Model
  var progress: Progress
  /// Running segment requests, kept for cancellation. Keyed by
  /// `ObjectIdentifier`: `taskIdentifier` repeats across the session pool.
  var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
  /// Files opened and not yet promoted into the HF cache -- downloading, or
  /// all in and being verified. Keyed by remote URL. The download is done when
  /// the last one is promoted.
  var writers: [URL: PartialWriter] = [:]
  /// Bytes belonging to files that have already completed (hash-verified and promoted into HF cache).
  var completedFilesBytes: Int64 = 0
  /// HF download plan (commit hash + blob hashes) needed to write into the HF
  /// cache layout. Nil between placeholder creation and the async metadata
  /// fetch completing. Shares this entry's lifecycle, so it can't drift out of
  /// sync with the download the way a parallel dict would.
  var plan: HFDownloadPlan?
  /// Retry attempts consumed per segment (exponential-backoff budget).
  /// Living here, the counters die with the entry — teardown and completion
  /// need no separate cleanup, and a later resume starts a fresh budget.
  var retryAttempts: [SegmentKey: Int] = [:]
  /// True when every file left has all its bytes and only verification
  /// remains -- the hash runs after the last byte (segments land out of order,
  /// so it can't run alongside), which takes seconds on a large file.
  var isVerifying = false
  /// When the last progress notification was posted (UI refresh throttle).
  var lastNotified: Date = .distantPast
  /// Recent (time, completed-bytes) samples backing the live rate readout.
  /// Appended on every `refreshProgress` tick, pruned to `rateWindow`. A
  /// trailing-window average keeps the displayed figure lively but not jumpy.
  var rateSamples: [(time: Date, bytes: Int64)] = []

  /// How far back the rate average looks.
  private static let rateWindow: TimeInterval = 5

  /// Current transfer rate in bytes/sec, averaged over `rateWindow`.
  /// Nil until the window holds at least a second of data — a shorter span
  /// makes the first readouts wildly noisy.
  var bytesPerSecond: Int64? {
    guard let first = rateSamples.first, let last = rateSamples.last else { return nil }
    let span = last.time.timeIntervalSince(first.time)
    guard span >= 1 else { return nil }
    // Clamp: a negative rate must never reach the UI.
    return max(0, Int64(Double(last.bytes - first.bytes) / span))
  }

  mutating func addTask(_ task: URLSessionDataTask) {
    tasks[ObjectIdentifier(task)] = task
  }

  mutating func removeTask(_ key: ObjectIdentifier) {
    tasks.removeValue(forKey: key)
  }

  /// Refreshes `progress` from caller-supplied byte sums across in-flight files.
  /// `activeBytes` is the total bytes currently on disk across all in-flight `.partial` files;
  /// `expectedActiveBytes` is the sum of their full sizes.
  mutating func refreshProgress(activeBytes: Int64, expectedActiveBytes: Int64) {
    let totalCompleted = completedFilesBytes + activeBytes
    // Don't shrink totalUnitCount — it's seeded from the HF resolve's
    // aggregated byte count, and writers open (adding their sizes) only after
    // the download is registered.
    let totalExpected = max(progress.totalUnitCount, completedFilesBytes + expectedActiveBytes)
    progress.totalUnitCount = max(totalExpected, 1)
    progress.completedUnitCount = totalCompleted

    // Feed the rate window.
    let now = Date()
    rateSamples.append((time: now, bytes: totalCompleted))
    rateSamples.removeAll { now.timeIntervalSince($0.time) > Self.rateWindow }
  }
}
