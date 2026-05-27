import CommonCrypto
import Foundation
import os.log

/// Utility for working with the standard HuggingFace Hub cache layout.
///
/// Layout:
/// ```
/// ~/.cache/huggingface/hub/
/// └── models--{org}--{repo}/
///     ├── blobs/
///     │   └── {sha256}              # actual file, named by content hash
///     ├── refs/
///     │   └── main                  # text file containing commit hash
///     └── snapshots/
///         └── {commit}/
///             └── filename.gguf -> ../../blobs/{sha256}
/// ```
enum HFCache {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "HFCache")

  // MARK: - Path Helpers (pure, no I/O)

  /// Parses a HF download URL and returns the repo directory name.
  /// e.g. `https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/file.gguf`
  /// → `"models--unsloth--Qwen3.5-2B-GGUF"`
  static func repoDirName(from url: URL) -> String? {
    // Path components: ["", "unsloth", "Qwen3.5-2B-GGUF", "resolve", "main", "file.gguf"]
    let components = url.pathComponents
    guard components.count >= 4,
      components[3] == "resolve"
    else { return nil }
    let org = components[1]
    let repo = components[2]
    return "models--\(org)--\(repo)"
  }

  /// The repo-relative path a HF download URL points at (everything past
  /// `resolve/{branch}/`), preserving subdir structure. e.g.
  /// `https://huggingface.co/org/repo/resolve/main/Q4_K_M/model.gguf`
  /// → `"Q4_K_M/model.gguf"`.
  /// Returns nil for URLs that don't match the HF resolve shape.
  static func repoRelativePath(from url: URL) -> String? {
    // ["", org, repo, "resolve", branch, ...rest]
    let components = url.pathComponents
    guard components.count >= 6,
      components[3] == "resolve"
    else { return nil }
    return components[5...].joined(separator: "/")
  }

  /// Path to a blob file in the HF cache.
  static func blobPath(cacheDir: URL, repoDir: String, sha256: String) -> URL {
    cacheDir
      .appendingPathComponent(repoDir)
      .appendingPathComponent("blobs")
      .appendingPathComponent(sha256)
  }

  /// Path to a file's symlink in a snapshot directory.
  static func snapshotPath(
    cacheDir: URL, repoDir: String, commit: String, filename: String
  ) -> URL {
    cacheDir
      .appendingPathComponent(repoDir)
      .appendingPathComponent("snapshots")
      .appendingPathComponent(commit)
      .appendingPathComponent(filename)
  }

  /// Path to the refs/main file for a repo.
  static func refsMainPath(cacheDir: URL, repoDir: String) -> URL {
    cacheDir
      .appendingPathComponent(repoDir)
      .appendingPathComponent("refs")
      .appendingPathComponent("main")
  }

  /// Directory that holds in-progress `.partial` files for a model.
  /// Lives under the HF cache so promoting `.partial` → `blobs/<hash>` stays on the
  /// same filesystem (moveItem is atomic).
  static func partialDir(cacheDir: URL, modelId: String) -> URL {
    cacheDir
      .appendingPathComponent(".llamabarn-partial")
      .appendingPathComponent(modelId)
  }

  /// Path to an in-progress `.partial` file for a single remote file.
  static func partialPath(cacheDir: URL, modelId: String, filename: String) -> URL {
    partialDir(cacheDir: cacheDir, modelId: modelId)
      .appendingPathComponent("\(filename).partial")
  }

  /// Removes the model's partial directory (and any files under it).
  /// Silently ignores missing dirs — used by cancel/delete/cleanup paths.
  static func removePartials(cacheDir: URL, modelId: String) {
    let dir = partialDir(cacheDir: cacheDir, modelId: modelId)
    try? FileManager.default.removeItem(at: dir)
  }

  /// Sum of `.partial` file sizes in a single model's staging dir.
  /// Returns 0 if the dir doesn't exist or contains no `.partial` files.
  ///
  /// Walks recursively — some HF repos nest GGUFs in per-quant subdirs
  /// (e.g. `Q4_K_M/model.gguf`), and the partial layout mirrors the repo
  /// layout, so partials can live one level deep.
  static func partialBytes(cacheDir: URL, modelId: String) -> Int64 {
    let dir = partialDir(cacheDir: cacheDir, modelId: modelId)
    let fm = FileManager.default
    guard
      let enumerator = fm.enumerator(
        at: dir,
        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else { return 0 }

    var total: Int64 = 0
    for case let url as URL in enumerator {
      guard url.pathExtension == "partial" else { continue }
      guard
        let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
        vals.isRegularFile == true
      else { continue }
      total += Int64(vals.fileSize ?? 0)
    }
    return total
  }

  /// Cleans up `.llamabarn-partial/<id>` subdirs for ids that are already
  /// installed (e.g. a deeplink download that landed but left its partial dir
  /// behind). We don't surface remaining partials as paused-download rows on
  /// startup — there's no in-memory `Model` for them without a deeplink to
  /// rebuild from. Re-clicking the deeplink rebuilds the entry with the same
  /// id and `openPartialWriter` resumes from the on-disk bytes.
  static func cleanInstalledPartials(cacheDir: URL, installedIds: Set<String>) {
    let root = cacheDir.appendingPathComponent(".llamabarn-partial")
    guard let subdirs = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
      return
    }
    for modelId in subdirs where installedIds.contains(modelId) {
      try? FileManager.default.removeItem(at: root.appendingPathComponent(modelId))
    }
  }

  // MARK: - API Calls

  /// Metadata returned by a HEAD request to a HF file URL.
  struct FileMetadata {
    /// Content hash (SHA256) from X-Linked-Etag or ETag header.
    /// Nil if neither header contains a valid SHA256.
    let blobHash: String?
    /// Repo commit hash from the X-Repo-Commit header.
    /// Nil if the header is missing.
    let commitHash: String?
  }

  /// Fetches blob hash and commit hash for multiple files via HEAD requests.
  ///
  /// HF serves `X-Linked-Etag` (blob SHA256) and `X-Repo-Commit` (commit hash) in
  /// the response to the resolve URL. We use a same-host redirect delegate to prevent
  /// following redirects to the CDN, which would lose these headers.
  ///
  /// Uses a single URLSession for all requests (sessions are heavyweight).
  static func fetchFileMetadata(
    for urls: [URL], token: String?
  ) async -> [URL: FileMetadata] {
    let delegate = SameHostRedirectDelegate()
    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }

    var results: [URL: FileMetadata] = [:]

    for url in urls {
      var request = URLRequest(url: url)
      request.httpMethod = "HEAD"
      if let token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      }

      guard let (_, response) = try? await session.data(for: request),
        let httpResponse = response as? HTTPURLResponse,
        (200...399).contains(httpResponse.statusCode)
      else { continue }

      // Extract blob hash from X-Linked-Etag (preferred) or ETag (fallback)
      let blobHash: String? = {
        if let etag = httpResponse.value(forHTTPHeaderField: "X-Linked-Etag") {
          return etag.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
          let cleaned =
            etag
            .replacingOccurrences(of: "W/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
          // Only use if it looks like a SHA256 (64 hex chars)
          if cleaned.count == 64, cleaned.allSatisfy({ $0.isHexDigit }) {
            return cleaned
          }
        }
        return nil
      }()

      let commitHash = httpResponse.value(forHTTPHeaderField: "X-Repo-Commit")
      results[url] = FileMetadata(blobHash: blobHash, commitHash: commitHash)
    }

    return results
  }

  // MARK: - File Operations

  /// Writes a downloaded file into the HF cache layout.
  ///
  /// 1. Creates directory structure (blobs/, snapshots/{commit}/, refs/)
  /// 2. Moves temp file → blobs/{sha256}
  /// 3. Creates symlink snapshots/{commit}/{filename} → ../../blobs/{sha256}
  /// 4. Writes refs/main with the commit hash
  static func writeBlobAndLink(
    cacheDir: URL,
    repoDir: String,
    commit: String,
    blobHash: String,
    filename: String,
    from tempFile: URL
  ) throws {
    let fm = FileManager.default

    let repoBase = cacheDir.appendingPathComponent(repoDir)
    let blobsDir = repoBase.appendingPathComponent("blobs")
    let snapshotDir = repoBase.appendingPathComponent("snapshots").appendingPathComponent(commit)
    let refsDir = repoBase.appendingPathComponent("refs")

    // Create directories
    try fm.createDirectory(at: blobsDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: refsDir, withIntermediateDirectories: true)

    // Move temp file to blob (atomic within same filesystem).
    // If blob already exists (identical content from concurrent download), just clean up temp.
    let blobDest = blobsDir.appendingPathComponent(blobHash)
    if fm.fileExists(atPath: blobDest.path) {
      try? fm.removeItem(at: tempFile)
    } else {
      try fm.moveItem(at: tempFile, to: blobDest)
    }

    // Create symlink: snapshots/{commit}/{filename} → ../../blobs/{sha256}
    // `filename` is repo-relative and may contain a subdir (e.g.
    // `Q4_K_M/model.gguf`). In that case:
    //   - the symlink's parent (`snapshots/{commit}/Q4_K_M/`) has to exist, and
    //   - the relative target needs one extra `..` per extra path component
    //     because we're one directory deeper than the flat case.
    let symlinkPath = snapshotDir.appendingPathComponent(filename)
    try fm.createDirectory(
      at: symlinkPath.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    if fm.fileExists(atPath: symlinkPath.path)
      || (try? fm.destinationOfSymbolicLink(atPath: symlinkPath.path)) != nil
    {
      try? fm.removeItem(at: symlinkPath)
    }
    let depth = filename.split(separator: "/").count - 1  // 0 for flat, 1 for one subdir, etc.
    let relativeTarget = String(repeating: "../", count: 2 + depth) + "blobs/\(blobHash)"
    try fm.createSymbolicLink(atPath: symlinkPath.path, withDestinationPath: relativeTarget)

    // Write refs/main with commit hash
    let refsMainFile = refsDir.appendingPathComponent("main")
    try commit.write(to: refsMainFile, atomically: true, encoding: .utf8)

    logger.info("Wrote HF cache: \(repoDir)/blobs/\(blobHash) + snapshot symlink for \(filename)")
  }

  /// Incremental SHA256 hasher. Used by the resumable download path:
  /// we stream bytes into the hasher as they're written to the `.partial` file
  /// (and re-hash any existing prefix once at resume time) so the final digest
  /// is ready at completion without a second full-file pass.
  final class SHA256Hasher {
    private var ctx = CC_SHA256_CTX()
    init() { CC_SHA256_Init(&ctx) }

    func update(_ data: Data) {
      guard !data.isEmpty else { return }
      data.withUnsafeBytes { ptr in
        _ = CC_SHA256_Update(&ctx, ptr.baseAddress, CC_LONG(ptr.count))
      }
    }

    func finalize() -> String {
      var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
      CC_SHA256_Final(&digest, &ctx)
      return digest.map { String(format: "%02x", $0) }.joined()
    }
  }

  /// Feeds the entire contents of `fileURL` into `hasher` in 1 MB chunks.
  /// Used on resume to reconstruct the running hash over the existing `.partial` prefix.
  static func feedHasher(_ hasher: SHA256Hasher, from fileURL: URL) throws {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    let chunkSize = 1_048_576  // 1 MB
    while autoreleasepool(invoking: {
      let data = handle.readData(ofLength: chunkSize)
      guard !data.isEmpty else { return false }
      hasher.update(data)
      return true
    }) {}
  }

  /// Computes SHA256 of a file using streaming 1MB chunks.
  /// Used as fallback when the HEAD request doesn't provide the hash.
  static func computeSHA256(of fileURL: URL) throws -> String {
    let hasher = SHA256Hasher()
    try feedHasher(hasher, from: fileURL)
    return hasher.finalize()
  }

  // MARK: - Deletion

  /// Deletes a model's files from the HF cache.
  /// Removes blobs (resolved from symlinks), snapshot symlinks, and cleans up empty dirs.
  static func deleteModelFiles(cacheDir: URL, repoDir: String, paths: ResolvedPaths) throws {
    let fm = FileManager.default
    var blobsToDelete: Set<String> = []
    var symlinksToDelete: [String] = []

    // Collect blob paths by following symlinks
    for path in paths.allPaths {
      // Check if it's a symlink and resolve the blob
      if let dest = try? fm.destinationOfSymbolicLink(atPath: path) {
        // dest is relative like "../../blobs/{hash}", resolve it
        let symlinkDir = URL(fileURLWithPath: path).deletingLastPathComponent()
        let blobAbsolute = symlinkDir.appendingPathComponent(dest).standardized.path
        blobsToDelete.insert(blobAbsolute)
        symlinksToDelete.append(path)
      } else if fm.fileExists(atPath: path) {
        // Direct file (not a symlink) — just delete it
        try fm.removeItem(atPath: path)
      }
    }

    // Delete symlinks first, then blobs
    for symlink in symlinksToDelete {
      try? fm.removeItem(atPath: symlink)
    }
    for blob in blobsToDelete {
      if fm.fileExists(atPath: blob) {
        try fm.removeItem(atPath: blob)
      }
    }

    // Clean up empty directories
    let repoBase = cacheDir.appendingPathComponent(repoDir)
    cleanEmptyDirs(at: repoBase)
  }

  /// Recursively removes empty directories under the given path.
  /// Removes the path itself if it becomes empty.
  private static func cleanEmptyDirs(at url: URL) {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else { return }

    for item in contents {
      let itemUrl = url.appendingPathComponent(item)
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: itemUrl.path, isDirectory: &isDir), isDir.boolValue {
        cleanEmptyDirs(at: itemUrl)
      }
    }

    // Check again after cleaning subdirs
    if let remaining = try? fm.contentsOfDirectory(atPath: url.path), remaining.isEmpty {
      try? fm.removeItem(at: url)
    }
  }

  // MARK: - Scanning

  // MARK: - Discovery

  /// Scans the HF cache for GGUF files and builds a `Model` + `ResolvedPaths`
  /// per discovered file (or shard group).
  ///
  /// For each GGUF, metadata is parsed from the repo directory name and
  /// filename using the same approach as llama.cpp's WebUI model selector.
  /// Split GGUFs (e.g. -00001-of-00003.gguf) are grouped as single entries.
  static func scanForSideloaded(
    cacheDir: URL
  ) -> [(entry: Model, paths: ResolvedPaths)] {
    let fm = FileManager.default
    var results: [(entry: Model, paths: ResolvedPaths)] = []

    guard let repoDirs = try? fm.contentsOfDirectory(atPath: cacheDir.path) else {
      return results
    }

    for repoDir in repoDirs {
      guard repoDir.hasPrefix("models--") else { continue }

      let snapshotsDir =
        cacheDir
        .appendingPathComponent(repoDir)
        .appendingPathComponent("snapshots")

      guard let commits = try? fm.contentsOfDirectory(atPath: snapshotsDir.path) else {
        continue
      }

      // Track which model IDs we've already found in this repo
      // (same model may appear in multiple snapshots)
      var seenIds: Set<String> = []

      // Check all snapshot commits, not just the first — a repo may have
      // multiple commits with different files. `seenIds` keeps duplicates out
      // of the result list.
      for commit in commits {
        let snapshotDir = snapshotsDir.appendingPathComponent(commit)

        // Collect GGUF files from the snapshot dir and one level of subdirs.
        // Some repos (e.g. unsloth) store sharded quants in per-quant subdirs
        // like Q4_K_M/model-00001-of-00003.gguf.
        // Paths are relative to snapshotDir (e.g. "file.gguf" or "Q4_K_M/file.gguf").
        guard let topFiles = try? fm.contentsOfDirectory(atPath: snapshotDir.path) else {
          continue
        }

        var allFiles: [String] = []
        for item in topFiles {
          let itemPath = snapshotDir.appendingPathComponent(item).path
          var isDir: ObjCBool = false
          if fm.fileExists(atPath: itemPath, isDirectory: &isDir), isDir.boolValue {
            if let subFiles = try? fm.contentsOfDirectory(atPath: itemPath) {
              for subFile in subFiles {
                allFiles.append("\(item)/\(subFile)")
              }
            }
          } else {
            allFiles.append(item)
          }
        }

        // Skip mmproj files (vision projection) — they're not runnable models.
        let ggufFiles = allFiles.filter { relativePath in
          let fileName = URL(fileURLWithPath: relativePath).lastPathComponent.lowercased()
          return fileName.hasSuffix(".gguf") && !fileName.hasPrefix("mmproj")
        }

        guard !ggufFiles.isEmpty else { continue }

        // Group split shards: "model-00001-of-00003.gguf" etc.
        // Key: shard base name → [all shard filenames sorted]
        var shardGroups: [String: [String]] = [:]
        var standaloneFiles: [String] = []

        for filename in ggufFiles {
          if HFRepoParser.isSplitShard(filename) {
            if let baseName = HFRepoParser.splitShardBaseName(filename) {
              shardGroups[baseName, default: []].append(filename)
            }
          } else {
            standaloneFiles.append(filename)
          }
        }

        // Process standalone GGUF files (one entry per file)
        for filename in standaloneFiles {
          if let result = buildSideloadedEntry(
            repoDir: repoDir, filename: filename, shardFiles: nil,
            snapshotDir: snapshotDir, fm: fm
          ), seenIds.insert(result.entry.id).inserted {
            results.append(result)
          }
        }

        // Process split shard groups (one entry per group, using first shard)
        for (_, shardFilenames) in shardGroups {
          let sorted = shardFilenames.sorted()
          // Only include groups where the first shard exists
          guard let firstShard = sorted.first,
            HFRepoParser.isFirstShard(firstShard)
          else { continue }

          if let result = buildSideloadedEntry(
            repoDir: repoDir, filename: firstShard, shardFiles: sorted,
            snapshotDir: snapshotDir, fm: fm
          ), seenIds.insert(result.entry.id).inserted {
            results.append(result)
          }
        }
      }
    }

    return results
  }

  /// Builds a `Model` + `ResolvedPaths` from a discovered GGUF file.
  ///
  /// Quant derivation uses `GGUFQuantLabel.parse` first and falls back to
  /// `HFRepoParser.parseQuant` — this makes deeplink-originated installs and
  /// scan-discovered installs agree on `{org}/{repo}:{QUANT}` so they round-trip.
  private static func buildSideloadedEntry(
    repoDir: String,
    filename: String,
    shardFiles: [String]?,
    snapshotDir: URL,
    fm: FileManager
  ) -> (entry: Model, paths: ResolvedPaths)? {
    // Parse metadata from repo dir name
    guard let parsed = HFRepoParser.parse(repoDir: repoDir) else { return nil }

    // Parse quantization. `GGUFQuantLabel` runs the full HF grammar against the
    // whole repo-relative path, so it catches the label whether it's in a subdir
    // prefix (`Q4_K_M/model.gguf`), in the filename (`model-Q4_K_M.gguf`), or
    // wearing an Unsloth `UD-` prefix. This is load-bearing for identity: the
    // deeplink resolver builds `{org}/{repo}:{QUANT}` using the same function,
    // and `updateDownloadedModels` cleans up pending rows by id match —
    // diverging grammars here means pending entries never get reaped.
    // `HFRepoParser.parseQuant` is the fallback for legacy flat filenames
    // where the label sits outside the HF enum but still starts with Q/F/IQ.
    let fileBaseName = URL(fileURLWithPath: filename).lastPathComponent
    let quant =
      GGUFQuantLabel.parse(filename)
      ?? HFRepoParser.parseQuant(filename: fileBaseName)
      ?? "unknown"

    // Calculate file size (sum all shards if split)
    let filePaths: [String]
    if let shardFiles {
      filePaths = shardFiles.map { snapshotDir.appendingPathComponent($0).path }
    } else {
      filePaths = [snapshotDir.appendingPathComponent(filename).path]
    }

    // Resolve symlinks before reading attributes — HF cache stores symlinks in
    // snapshot dirs pointing to blobs, and attributesOfItem returns the symlink
    // size (not the target file size) for symlinks.
    let totalFileSize: Int64 = filePaths.reduce(0) { sum, path in
      let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
      let attrs = try? fm.attributesOfItem(atPath: resolved)
      return sum + ((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
    }

    // Generate stable ID matching llama-server's `-hf` shorthand format:
    // "{org}/{repo}:{QUANT}" -- e.g. "ggml-org/gemma-3-1b-it-qat-GGUF:Q4_0".
    // This lets power users switch b/w llama-server and LlamaBarn w/o changing
    // model IDs in their code.
    // Extract repo name from "models--org--repo"
    let repoParts = repoDir.components(separatedBy: "--")
    let repoName = repoParts.count >= 3 ? repoParts[2...].joined(separator: "--") : repoDir
    let modelId = "\(parsed.org)/\(repoName):\(quant)"

    // Build the display size label — use params if available, otherwise show quant only
    let sizeLabel = parsed.params ?? quant

    let entry = Model(
      id: modelId,
      family: parsed.name,
      size: sizeLabel,
      ctxWindow: 131_072,  // 128k upper bound — clamped by memory budget
      fileSize: totalFileSize,
      // ctxBytesPer1kTokens stays 0 until the async MemProfile probe runs.
      downloadUrl: URL(string: "file:///")!,
      org: parsed.org,
      tags: parsed.tags,
      quantization: quant
    )

    // Build resolved paths
    let mainFilePath = snapshotDir.appendingPathComponent(filename).path
    let additionalParts: [String]
    if let shardFiles, shardFiles.count > 1 {
      // Additional shards = everything except the first shard
      additionalParts = shardFiles.dropFirst().map {
        snapshotDir.appendingPathComponent($0).path
      }
    } else {
      additionalParts = []
    }

    let paths = ResolvedPaths(
      modelFile: mainFilePath,
      additionalParts: additionalParts,
      mmprojFile: nil,
      hfRepoDirName: repoDir
    )

    return (entry: entry, paths: paths)
  }
}

// MARK: - Same-Host Redirect Delegate

/// URLSession delegate that blocks cross-host redirects.
/// HF redirects file URLs to a CDN for the actual download. The CDN response
/// won't have HF-specific headers (X-Linked-Etag, X-Repo-Commit). By blocking
/// the redirect, the HEAD request returns HF's 302 response with those headers intact.
private class SameHostRedirectDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    // Allow same-host redirects (e.g., HTTP → HTTPS), block cross-host (HF → CDN)
    if task.originalRequest?.url?.host == request.url?.host {
      completionHandler(request)
    } else {
      completionHandler(nil)
    }
  }
}

// MARK: - Errors

enum HFCacheError: Error, LocalizedError {
  case invalidUrl(String)
  case apiError(String)

  var errorDescription: String? {
    switch self {
    case .invalidUrl(let url): return "Invalid HF URL: \(url)"
    case .apiError(let msg): return "HF API error: \(msg)"
    }
  }
}
