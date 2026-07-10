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

  /// Name of the hidden dir under the HF cache that holds in-progress `.partial`
  /// files. Tied to the app's "llama" identity; `RenameMigration` moves the
  /// pre-rename `.llamabarn-partial` dir here on first launch.
  static let partialRootDirName = ".llama-partial"

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
      .appendingPathComponent(partialRootDirName)
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

  /// File name of the per-download placeholder dropped next to a model's
  /// `.partial` files. Hidden (leading dot) and not a `.partial`, so
  /// `partialBytes` ignores it; it rides inside the partial dir so the existing
  /// `removePartials` cleanup disposes of it on completion/cancel.
  static let placeholderFileName = ".model.json"

  /// Path to a download's placeholder file (the serialized `Model`). Written
  /// when a download starts so the app can rebuild the paused row at launch
  /// without a network resolve; see `scanPlaceholders`.
  static func placeholderURL(cacheDir: URL, modelId: String) -> URL {
    partialDir(cacheDir: cacheDir, modelId: modelId)
      .appendingPathComponent(placeholderFileName)
  }

  /// Finds every download placeholder under the partial root — one per
  /// interrupted/paused download from a previous session. Used at launch to
  /// rehydrate paused rows. Returns the placeholder file URLs; the caller
  /// decodes the `Model` (HFCache stays model-agnostic).
  static func scanPlaceholders(cacheDir: URL) -> [URL] {
    let root = cacheDir.appendingPathComponent(partialRootDirName)
    guard
      let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    else { return [] }
    var result: [URL] = []
    for case let url as URL in enumerator where url.lastPathComponent == placeholderFileName {
      result.append(url)
    }
    return result
  }

  /// Cleans up `<partialRootDirName>/<id>` subdirs for ids that are already
  /// installed (e.g. a deeplink download that landed but left its partial dir
  /// behind). Interrupted (not-yet-installed) downloads are kept and surfaced
  /// as paused rows at launch via `scanPlaceholders`.
  static func cleanInstalledPartials(cacheDir: URL, installedIds: Set<String>) {
    let root = cacheDir.appendingPathComponent(partialRootDirName)
    guard let subdirs = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
      return
    }
    for modelId in subdirs where installedIds.contains(modelId) {
      try? FileManager.default.removeItem(at: root.appendingPathComponent(modelId))
    }
  }

  /// Returns true if `filename` (repo-relative) exists in any snapshot commit
  /// of the repo — i.e. the file is already installed in the cache.
  static func snapshotFileExists(cacheDir: URL, repoDir: String, filename: String) -> Bool {
    let snapshotsDir =
      cacheDir
      .appendingPathComponent(repoDir)
      .appendingPathComponent("snapshots")

    guard let commits = try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path)
    else { return false }

    return commits.contains { commit in
      let filePath = snapshotsDir.appendingPathComponent(commit).appendingPathComponent(filename)
      return FileManager.default.fileExists(atPath: filePath.path)
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
        let ggufFiles = collectGgufFiles(in: snapshotDir, fm: fm)
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
          // Only include complete groups: first shard present AND every shard of
          // the declared `-of-NNNNN` count on disk. Shards are promoted into the
          // snapshot one by one as each finishes downloading, so a mid-download
          // scan can see a partial set — treating that as installed would make
          // the model appear twice (installed + downloading) and lets the
          // partials GC delete the in-flight download's staging files.
          guard let firstShard = sorted.first,
            HFRepoParser.isFirstShard(firstShard),
            sorted.count == HFRepoParser.shardTotal(firstShard)
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

  /// Collects runnable GGUF files from a snapshot dir and one level of subdirs.
  /// Some repos (e.g. unsloth) store sharded quants in per-quant subdirs like
  /// Q4_K_M/model-00001-of-00003.gguf. Returned paths are relative to
  /// `snapshotDir` (e.g. "file.gguf" or "Q4_K_M/file.gguf"). Skips mmproj files
  /// (vision projection) — they're not runnable models.
  private static func collectGgufFiles(in snapshotDir: URL, fm: FileManager) -> [String] {
    guard let topFiles = try? fm.contentsOfDirectory(atPath: snapshotDir.path) else {
      return []
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

    return allFiles.filter { relativePath in
      // Skip mmproj (vision projection) and mtp- (speculative draft head)
      // sidecars -- neither is a runnable model on its own.
      relativePath.lowercased().hasSuffix(".gguf")
        && !SidecarPicker.isMmproj(relativePath)
        && !SidecarPicker.isMtp(relativePath)
    }
  }

  /// Builds a `Model` + `ResolvedPaths` from a discovered GGUF file.
  ///
  /// Quant tags come from `GGUFQuant.tag(forPath:)` — the same derivation the
  /// deeplink resolver uses, so deeplink-originated installs and
  /// scan-discovered installs agree on `{org}/{repo}:{TAG}` and round-trip.
  private static func buildSideloadedEntry(
    repoDir: String,
    filename: String,
    shardFiles: [String]?,
    snapshotDir: URL,
    fm: FileManager
  ) -> (entry: Model, paths: ResolvedPaths)? {
    // Parse metadata from repo dir name
    guard let parsed = HFRepoParser.parse(repoDir: repoDir) else { return nil }

    // Derive the quant tag. This is load-bearing for identity: the deeplink
    // resolver builds `{org}/{repo}:{TAG}` through the same function, and
    // `updateDownloadedModels` cleans up pending rows by id match — a
    // diverging derivation here means pending entries never get reaped.
    let quant = GGUFQuant.tag(forPath: filename)

    // Locate the vision projector (`mmproj*.gguf`) sidecar, if the repo ships
    // one. Vision models can't do image input without it, and this scan path is
    // the sole source of `resolvedPaths` for `models.ini` — so if we don't
    // attach it here, the `mmproj =` line never gets written and vision
    // silently fails even though the sidecar is on disk.
    let mmprojFile = findMmprojSidecar(snapshotDir: snapshotDir, mainRelPath: filename, fm: fm)

    // Calculate file size (sum all shards if split, plus the mmproj sidecar so
    // it matches `Model.fileSize`'s contract: main + shards + mmproj).
    var filePaths: [String]
    if let shardFiles {
      filePaths = shardFiles.map { snapshotDir.appendingPathComponent($0).path }
    } else {
      filePaths = [snapshotDir.appendingPathComponent(filename).path]
    }
    if let mmprojFile {
      filePaths.append(mmprojFile)
    }

    // Resolve symlinks before reading attributes — HF cache stores symlinks in
    // snapshot dirs pointing to blobs, and attributesOfItem returns the symlink
    // size (not the target file size) for symlinks.
    let totalFileSize: Int64 = filePaths.reduce(0) { sum, path in
      let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
      return sum + fm.fileSize(atPath: resolved)
    }

    // Generate the stable ID via the shared grammar: native (ggml-org) models
    // get a short slashless id; other orgs keep "{org}/{repo}:{QUANT}", which
    // matches llama-server's `-hf` shorthand so power users can switch b/w
    // llama-server and Llama w/o changing model IDs in their code.
    let modelId = Model.makeId(org: parsed.org, repo: parsed.repo, tag: quant)

    let entry = Model(
      id: modelId,
      family: parsed.name,
      ctxWindow: 131_072,  // 128k upper bound — clamped by memory budget
      fileSize: totalFileSize,
      // ctxBytesPer1kTokens stays 0 until the async MemProfile probe runs.
      downloadUrl: URL(string: "file:///")!,
      org: parsed.org
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

    // A sidecar MTP head (`mtp-….gguf`) shipped beside the main weights, if any,
    // quant-matched to the main. Present takes precedence over an embedded head.
    let mtpSidecar = findMTPSidecar(
      snapshotDir: snapshotDir, mainRelPath: filename, mainQuant: quant, fm: fm)

    // Embedded-head detection reads the GGUF metadata (the ground truth --
    // unsloth's MTP builds carry no filename marker at all), falling back to
    // the filename heuristic only when the header can't be parsed. This must
    // stay conservative: wrongly emitting `spec-type = draft-mtp` for a
    // headless model makes llama-server fail to load it entirely.
    let hasEmbeddedHead =
      GGUFMetadata.hasEmbeddedMTPHead(path: mainFilePath)
      ?? fileHasMTPHead(URL(fileURLWithPath: filename).lastPathComponent)

    let paths = ResolvedPaths(
      modelFile: mainFilePath,
      additionalParts: additionalParts,
      mmprojFile: mmprojFile,
      usesMTP: mtpSidecar == nil && hasEmbeddedHead,
      mtpSidecarFile: mtpSidecar,
      hfRepoDirName: repoDir
    )

    return (entry: entry, paths: paths)
  }

  /// Filename fallback for embedded-MTP detection, used only when the GGUF
  /// header can't be parsed (see `GGUFMetadata.hasEmbeddedMTPHead`). Some
  /// builds tag themselves with an `mtp` token delimited by the usual filename
  /// separators -- e.g. `Qwen3.6-27B-Q4_K_M-mtp.gguf` or
  /// `Qwen3.6-27B-MTP-Q8_0.gguf`. We match the delimited token (not a bare
  /// substring) so an unrelated name can't trip it. There's no separate sidecar
  /// to download: the head rides inside the main file.
  private static func fileHasMTPHead(_ fileBaseName: String) -> Bool {
    fileBaseName.range(
      of: #"(^|[-_.])mtp([-_.]|$)"#,
      options: [.regularExpression, .caseInsensitive]) != nil
  }

  /// Finds a sidecar MTP draft head (`mtp-….gguf`) shipped beside the main file,
  /// returning its absolute path. Selection policy lives in `SidecarPicker.mtp`;
  /// sizes are measured on the resolved blob (snapshot entries are symlinks).
  /// Looks only in the main file's own directory, where the snapshot places its
  /// siblings.
  private static func findMTPSidecar(
    snapshotDir: URL, mainRelPath: String, mainQuant: String, fm: FileManager
  ) -> String? {
    // The head sits in the same (sub)dir as the main file within the snapshot.
    let mainDir = (mainRelPath as NSString).deletingLastPathComponent
    let searchDir =
      mainDir.isEmpty ? snapshotDir : snapshotDir.appendingPathComponent(mainDir)

    guard let entries = try? fm.contentsOfDirectory(atPath: searchDir.path) else {
      return nil
    }
    let chosen = SidecarPicker.mtp(among: entries, mainQuant: mainQuant) {
      fm.fileSize(atPath: searchDir.appendingPathComponent($0).resolvingSymlinksInPath().path)
    }
    return chosen.map { searchDir.appendingPathComponent($0).path }
  }

  /// Finds the vision projector (`mmproj*.gguf`) sidecar for the main file,
  /// returning its absolute path. Selection policy (lone candidate or skip)
  /// lives in `SidecarPicker.mmproj`, shared with the deeplink resolver.
  ///
  /// Search is two-tier to cover both real-world layouts: first the main file's
  /// own directory (per-quant repos ship `Q4_K_M/mmproj-….gguf` beside the
  /// quant), then the snapshot top level (flat Gemma-style repos, and unsloth
  /// subdir repos that keep one shared `mmproj-….gguf` at the root while the
  /// quants live in subdirs).
  private static func findMmprojSidecar(
    snapshotDir: URL, mainRelPath: String, fm: FileManager
  ) -> String? {
    let mainDir = (mainRelPath as NSString).deletingLastPathComponent
    let mainDirURL =
      mainDir.isEmpty ? snapshotDir : snapshotDir.appendingPathComponent(mainDir)

    // Prefer a sidecar in the main file's own directory; fall back to the
    // snapshot root only when the main file lives in a subdir.
    if let hit = singleMmproj(in: mainDirURL, fm: fm) { return hit }
    if !mainDir.isEmpty, let hit = singleMmproj(in: snapshotDir, fm: fm) { return hit }
    return nil
  }

  /// Returns the lone `mmproj*.gguf` in `dir` (per `SidecarPicker.mmproj`'s
  /// policy) as an absolute path, or nil.
  private static func singleMmproj(in dir: URL, fm: FileManager) -> String? {
    guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }
    return SidecarPicker.mmproj(among: entries).map { dir.appendingPathComponent($0).path }
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
