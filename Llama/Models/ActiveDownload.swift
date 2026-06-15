import Foundation

/// Paused download state. Carries the `Model` so deeplink-sideload
/// placeholders can still render a paused row after their active download
/// is torn down.
struct PausedDownload {
  let model: Model
  let bytesOnDisk: Int64
}

/// Tracks the progress of a multi-file model download.
///
/// Bytes-in-flight are tracked externally (ModelManager owns the per-task
/// `PartialWriter` state since we stream into `.partial` files ourselves now,
/// rather than relying on URLSession's `countOfBytesReceived`). The caller
/// passes current sums into `refreshProgress`.
struct ActiveDownload {
  let model: Model
  var progress: Progress
  var tasks: [Int: URLSessionDataTask]
  /// Bytes belonging to files that have already completed (hash-verified and promoted into HF cache).
  var completedFilesBytes: Int64 = 0
  /// HF download plan (commit hash + blob hashes) needed to write into the HF
  /// cache layout. Nil between placeholder creation and the async metadata
  /// fetch completing. Shares this entry's lifecycle, so it can't drift out of
  /// sync with the download the way a parallel dict would.
  var plan: HFDownloadPlan?

  mutating func addTask(_ task: URLSessionDataTask) {
    tasks[task.taskIdentifier] = task
  }

  mutating func removeTask(with identifier: Int) {
    tasks.removeValue(forKey: identifier)
  }

  mutating func markTaskFinished(_ task: URLSessionDataTask, fileSize: Int64) {
    tasks.removeValue(forKey: task.taskIdentifier)
    completedFilesBytes += fileSize
  }

  /// Refreshes `progress` from caller-supplied byte sums across active tasks.
  /// `activeBytes` is the total bytes currently on disk across all in-flight `.partial` files;
  /// `expectedActiveBytes` is the sum of each task's known total size (0 before the response arrives).
  mutating func refreshProgress(activeBytes: Int64, expectedActiveBytes: Int64) {
    let totalCompleted = completedFilesBytes + activeBytes
    // Don't shrink totalUnitCount — it's seeded from the HF resolve's
    // aggregated byte count and a response's Content-Length may be missing
    // until the first byte arrives.
    let totalExpected = max(progress.totalUnitCount, completedFilesBytes + expectedActiveBytes)
    progress.totalUnitCount = max(totalExpected, 1)
    progress.completedUnitCount = totalCompleted
  }

  var isEmpty: Bool { tasks.isEmpty }
}
