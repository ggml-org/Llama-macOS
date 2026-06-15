import Foundation

// MARK: - WriterTable

/// Thread-safe table of in-flight `PartialWriter`s, keyed by `URLSessionTask.taskIdentifier`.
///
/// Owns the serial queue that guards both the dictionary and the fields of the
/// writers it holds: a `PartialWriter`'s mutable state is only ever touched
/// inside `sync`, so the writers themselves need no further synchronization.
/// Encapsulating the dict + queue here gives the shared mutable state a single
/// owner, instead of a raw `nonisolated(unsafe)` field living on the otherwise
/// main-actor `ModelManager` — hence `@unchecked Sendable`.
final class WriterTable: @unchecked Sendable {
  private var writers: [Int: PartialWriter] = [:]
  private let queue = DispatchQueue(
    label: "app.llama.ModelManager.writers", qos: .userInitiated)

  /// Runs `body` with exclusive access to the writer table. The sole entry
  /// point — every read or mutation of a writer goes through here.
  func sync<T>(_ body: (inout [Int: PartialWriter]) -> T) -> T {
    queue.sync { body(&writers) }
  }
}

// MARK: - PartialWriter

/// Per-file streaming state: open `.partial` file handle, running SHA256 hash,
/// byte counters, the expected blob hash when known, plus the immutable
/// download context (model, cache dir, HF plan) the delegate callbacks need.
///
/// Carrying that context here is what lets the nonisolated URLSession delegate
/// methods run without any synchronous hop back to the main actor: everything
/// they read is either fixed at download-start time or lives on this writer.
///
/// Reference type so URLSession delegate callbacks can mutate fields without
/// re-storing into the table. All access is serialized on the owning
/// `WriterTable`'s queue, so it's safe across the main actor / delegate queue
/// boundary — hence `@unchecked Sendable`.
final class PartialWriter: @unchecked Sendable {
  let modelId: String
  /// The model this download belongs to. Snapshotted at start; immutable for
  /// the life of the transfer, so the delegate can report failures against it
  /// without looking the model up on the main actor.
  let model: Model
  /// HF cache root the finished blob is promoted into.
  let cacheDir: URL
  /// HF download plan (commit + repo dir) used by `writeBlobAndLink`.
  let plan: HFDownloadPlan
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
    model: Model, cacheDir: URL, plan: HFDownloadPlan,
    url: URL, filename: String, partialURL: URL,
    handle: FileHandle, hasher: HFCache.SHA256Hasher,
    bytesWritten: Int64, expectedBlobHash: String?
  ) {
    self.modelId = model.id
    self.model = model
    self.cacheDir = cacheDir
    self.plan = plan
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
