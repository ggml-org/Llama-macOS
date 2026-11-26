import Foundation

// MARK: - WriterTable

/// Thread-safe table of in-flight segment requests, keyed by the task's
/// `ObjectIdentifier` -- not `taskIdentifier`, which counts per session and so
/// repeats across `ModelManager`'s session pool.
///
/// Owns the serial queue that guards both the dictionary and the fields of the
/// writers it points at: a `PartialWriter`'s mutable state is only ever touched
/// inside `sync`, so the writers themselves need no further synchronization.
/// Encapsulating the dict + queue here gives the shared mutable state a single
/// owner, instead of a raw `nonisolated(unsafe)` field living on the otherwise
/// main-actor `ModelManager` — hence `@unchecked Sendable`.
final class WriterTable: @unchecked Sendable {
  private var entries: [ObjectIdentifier: SegmentTask] = [:]
  private let queue = DispatchQueue(
    label: "app.llama.ModelManager.writers", qos: .userInitiated)

  /// Runs `body` with exclusive access to the table. The sole entry point —
  /// every read or mutation of an entry or a writer goes through here.
  func sync<T>(_ body: (inout [ObjectIdentifier: SegmentTask]) -> T) -> T {
    queue.sync { body(&entries) }
  }
}

/// A running segment request: the file and segment its bytes belong to.
/// Holds the task, so its `ObjectIdentifier` (the table key) can't be reused
/// by a new task while the entry exists.
struct SegmentTask {
  let task: URLSessionDataTask
  let writer: PartialWriter
  let index: Int
}

/// Names one segment of one file across retries -- each attempt is a new task,
/// so the retry budget can't be keyed by the task.
struct SegmentKey: Hashable {
  let url: URL
  let index: Int
}

// MARK: - Segment

/// One byte range of a file, fetched by its own range request.
struct Segment: Codable {
  /// First byte of the range.
  let start: Int64
  /// One past the last byte.
  let end: Int64
  /// Bytes of the range on disk so far, counted from `start`. A segment fills
  /// front to back, so this is also where its next request resumes.
  var written: Int64

  /// File offset of the segment's next byte.
  var offset: Int64 { start + written }
  var remaining: Int64 { end - offset }
  var isDone: Bool { remaining <= 0 }
}

// MARK: - PartialState

/// Which bytes of a `.partial` file are in: the file's size and the segments
/// that tile `0..<size`.
///
/// Segments fill at the same time, so until the end the `.partial` has holes,
/// and its length says nothing about how much of it is there -- this is the
/// resume state. Saved beside the `.partial` as `<name>.partial.json`.
struct PartialState: Codable {
  let size: Int64
  var segments: [Segment]

  /// How many segments a file is split into at most -- the number of
  /// connections it's fetched over (see `ModelManager.sessions`). A single
  /// connection to HF's CDN tops out well below a fast link: measured on a
  /// GitHub runner, 16 MB/s when the CDN edge is cold, 122 MB/s warm, against
  /// 318-385 MB/s for 8 parallel ranges.
  static let maxSegments = 8

  /// Smallest range worth a request of its own; a small file (a draft head,
  /// an mmproj) gets fewer segments rather than slivers.
  static let minSegmentSize: Int64 = 16 * 1_048_576

  /// Lays out a file of `size` bytes whose first `prefix` bytes are already on
  /// disk: the prefix as one finished segment, the rest split evenly.
  init(size: Int64, prefix: Int64) {
    self.size = size
    var segments: [Segment] = []
    if prefix > 0 {
      segments.append(Segment(start: 0, end: prefix, written: prefix))
    }
    let rest = size - prefix
    if rest > 0 {
      let count = Int64(min(max(rest / Self.minSegmentSize, 1), Int64(Self.maxSegments)))
      for i in 0..<count {
        segments.append(
          Segment(
            start: prefix + rest * i / count,
            end: prefix + rest * (i + 1) / count,
            written: 0))
      }
    }
    self.segments = segments
  }

  var bytesDone: Int64 { segments.reduce(0) { $0 + $1.written } }
  var isComplete: Bool { segments.allSatisfy(\.isDone) }

  /// Where the state of the `.partial` at `partialURL` is saved.
  static func url(for partialURL: URL) -> URL {
    partialURL.appendingPathExtension("json")
  }

  /// The saved state of a `.partial`, or nil when there's none (or it can't
  /// be read).
  static func load(for partialURL: URL) -> PartialState? {
    guard let data = try? Data(contentsOf: url(for: partialURL)) else { return nil }
    return try? JSONDecoder().decode(PartialState.self, from: data)
  }

  /// Atomic, so a crash mid-save leaves the previous state rather than a torn
  /// file.
  func save(for partialURL: URL) throws {
    try JSONEncoder().encode(self).write(to: Self.url(for: partialURL), options: .atomic)
  }
}

// MARK: - PartialWriter

/// Per-file download state: open `.partial` file handle, the segment layout
/// with each segment's progress, the expected blob hash when known, plus the
/// immutable download context (model, cache dir, HF plan) the delegate
/// callbacks need. Shared by all the file's segment requests.
///
/// Carrying that context here is what lets the nonisolated URLSession delegate
/// methods run without any synchronous hop back to the main actor: everything
/// they read is either fixed at download-start time or lives on this writer.
///
/// Reference type so URLSession delegate callbacks can mutate fields without
/// re-storing into the table. All access to mutable fields is serialized on
/// the `WriterTable`'s queue, so it's safe across the main actor / delegate
/// queue boundary — hence `@unchecked Sendable`.
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
  /// SHA256 of the blob as advertised by HF (`X-Linked-Etag`), when available.
  /// Nil → we trust the computed digest instead.
  let expectedBlobHash: String?
  var state: PartialState
  /// Set once the file's last segment is in and verification has been claimed,
  /// so the file is verified once even when two paths reach "complete" (the
  /// last segment finishing, and a retry of a segment that turns out to have
  /// had all its bytes).
  var isFinalizing = false
  /// When `state` was last saved -- saves are throttled to `saveInterval`.
  private var lastSaved = Date()

  /// How often the state is saved mid-download. A crash or force-quit loses at
  /// most this much progress: the bytes are on disk, but unrecorded, so a
  /// resume fetches them again.
  private static let saveInterval: TimeInterval = 2

  init(
    model: Model, cacheDir: URL, plan: HFDownloadPlan,
    url: URL, filename: String, partialURL: URL,
    handle: FileHandle, state: PartialState, expectedBlobHash: String?
  ) {
    self.modelId = model.id
    self.model = model
    self.cacheDir = cacheDir
    self.plan = plan
    self.url = url
    self.filename = filename
    self.partialURL = partialURL
    self.handle = handle
    self.state = state
    self.expectedBlobHash = expectedBlobHash
  }

  /// Writes a chunk of segment `index`'s response at the segment's offset.
  /// Clamped to the segment's end, so a response that overruns its range can't
  /// spill into the next segment's bytes. Saves `state` every `saveInterval`.
  func write(_ data: Data, segment index: Int) throws {
    let segment = state.segments[index]
    let count = Int(min(Int64(data.count), segment.remaining))
    guard count > 0 else { return }
    try handle.seek(toOffset: UInt64(segment.offset))
    try handle.write(contentsOf: data.prefix(count))
    state.segments[index].written += Int64(count)

    if Date().timeIntervalSince(lastSaved) >= Self.saveInterval {
      saveState()
    }
  }

  /// Best-effort: a failed save only costs a resume some re-fetched bytes.
  func saveState() {
    try? state.save(for: partialURL)
    lastSaved = Date()
  }

  func closeHandle() {
    try? handle.close()
  }
}
