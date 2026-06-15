import Foundation
import os.log

/// Turns a `llama://install?repo=…` deeplink into a concrete file set:
/// a specific GGUF (possibly sharded) and an optional mmproj sidecar, all
/// expressed as HF resolve URLs we can hand to `ModelManager`.
///
/// File-selection priority:
///   1. Explicit `quant` → sibling whose `parseGGUFQuantLabel` matches.
///   2. No quant → mirror llama.cpp's `find_best_model` (try Q4_K_M tag,
///      then Q4_0, else fall back to largest fits-budget). Pre-filters
///      candidates by `memBudget` so a small Mac doesn't get handed a
///      too-big Q4_K_M; final fallback is "largest" rather than llama.cpp's
///      "first listed" (alphabetical) which would systematically pick BF16.
enum HFRepoResolver {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "HFRepoResolver")

  /// Everything needed to start a download for a resolved deeplink.
  struct Resolved {
    /// Stable sideloaded id — `"{org}/{repo}:{QUANT}"`. Matches the id shape
    /// `HFCache.buildSideloadedEntry` produces, so post-install the row keeps
    /// the same identity without any handoff.
    let modelId: String
    /// `"{org}/{repo}"` — mirrors the `repo` query param.
    let repo: String
    /// Canonical quant label, matching the sideloaded scan's id grammar.
    let quant: String
    /// Main GGUF URL (goes into `Model.downloadUrl`).
    let mainUrl: URL
    /// Sharded parts, if any (`-00002-of-NNNNN.gguf`, ...).
    let additionalParts: [URL]
    /// Optional mmproj sidecar.
    let mmprojUrl: URL?
    /// Size in bytes if the HF API disclosed it (aggregated across main+shards+mmproj).
    /// 0 when the API didn't return per-file sizes. We start the download either way;
    /// `fetchHFDownloadPlan` does HEAD requests that produce real byte counts.
    let approximateBytes: Int64
  }

  /// User-facing errors. All map to `NSAlert` surface text in `DeeplinkHandler`.
  enum ResolveError: LocalizedError {
    case invalidQuant(String)
    case repoNotFound(String)
    case gated(String)
    case networkUnavailable(String)
    case noGgufFiles(String)
    case quantNotFound(repo: String, quant: String)
    case shardMissing(repo: String, shard: String)
    case noCompatibleFile(repo: String)

    var errorDescription: String? {
      switch self {
      case .invalidQuant(let q):
        return "“\(q)” isn’t a known GGUF quantization label."
      case .repoNotFound(let repo):
        return "Hugging Face returned 404 for \(repo)."
      case .gated(let repo):
        return "\(repo) is gated or private."
      case .networkUnavailable:
        return "Couldn’t reach Hugging Face."
      case .noGgufFiles(let repo):
        return "\(repo) doesn’t contain any GGUF files."
      case .quantNotFound(let repo, let quant):
        return "No \(quant) file found in \(repo)."
      case .shardMissing(let repo, let shard):
        return "Shard \(shard) is missing from \(repo)."
      case .noCompatibleFile(let repo):
        return "No quantization in \(repo) fits this Mac’s memory budget."
      }
    }

    var recoverySuggestion: String? {
      switch self {
      case .gated:
        return "Open Settings and paste a Hugging Face access token that has access to this repo."
      case .networkUnavailable:
        return "Check your internet connection and try again."
      case .noCompatibleFile:
        return "Open the repo page on Hugging Face and pick a smaller quant manually."
      default:
        return nil
      }
    }
  }

  /// Resolves against the live HF API. Authenticates with the configured HF
  /// token so gated repos with a valid token succeed.
  static func resolve(
    repo: String,
    quant: String?,
    systemMemoryMb: UInt64,
    token: String?
  ) async throws -> Resolved {
    // Up-front validation: a malformed but present quant is a hard reject.
    // Otherwise a tampered link could silently install a different file by
    // falling through to default-quant resolution.
    if let quant, GGUFQuantLabel.parse(quant) == nil {
      throw ResolveError.invalidQuant(quant)
    }

    let siblings = try await fetchSiblings(repo: repo, token: token)
    guard !siblings.isEmpty else {
      throw ResolveError.noGgufFiles(repo)
    }

    let budgetMb = Model.memoryBudget(systemMemoryMb: systemMemoryMb)

    // File selection: pick the main GGUF (plus an optional canonical quant label).
    let pick = try selectMain(
      repo: repo, requestedQuant: quant,
      siblings: siblings, budgetMb: budgetMb
    )

    // Expand shards + attach mmproj.
    let shards = try expandShards(main: pick.rfilename, siblings: siblings, repo: repo)
    let mmproj = pickMmproj(repo: repo, siblings: siblings)

    // Aggregate size (main + shards + mmproj), dropping unknown entries.
    var allPicked: [String] = shards  // includes the main shard at index 0
    if let m = mmproj { allPicked.append(m.rfilename) }
    let sizeByPath: [String: Int64] = Dictionary(
      uniqueKeysWithValues: siblings.map { ($0.rfilename, $0.size ?? 0) })
    let approxBytes = allPicked.reduce(Int64(0)) { $0 + (sizeByPath[$1] ?? 0) }

    // `repo` is already validated as `{org}/{name}` upstream, so the sideloaded
    // id is just `{repo}:{QUANT}`.
    let modelId = "\(repo):\(pick.quant)"

    let mainUrl = resolveUrl(repo: repo, path: pick.rfilename)
    let extraUrls = shards.dropFirst().map { resolveUrl(repo: repo, path: $0) }
    let mmprojUrl = mmproj.map { resolveUrl(repo: repo, path: $0.rfilename) }

    return Resolved(
      modelId: modelId,
      repo: repo,
      quant: pick.quant,
      mainUrl: mainUrl,
      additionalParts: Array(extraUrls),
      mmprojUrl: mmprojUrl,
      approximateBytes: approxBytes
    )
  }

  // MARK: - HF API

  /// Minimal sibling representation — `rfilename` is repo-relative path
  /// (e.g. `Q4_K_M/model.gguf`), `size` is bytes when the API supplies it.
  struct Sibling: Decodable {
    let rfilename: String
    let size: Int64?
    private enum CodingKeys: String, CodingKey {
      case rfilename, size
    }
  }

  private struct ModelInfoResponse: Decodable {
    let siblings: [Sibling]?
  }

  private static func fetchSiblings(repo: String, token: String?) async throws -> [Sibling] {
    // `?blobs=true` asks HF to populate `siblings[].size` alongside filenames.
    // Without it, many responses omit sizes and we'd have to HEAD every
    // candidate just to rank them.
    guard let url = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true") else {
      throw ResolveError.repoNotFound(repo)
    }
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: req)
    } catch {
      logger.error("HF API fetch failed for \(repo): \(error.localizedDescription)")
      throw ResolveError.networkUnavailable(repo)
    }

    guard let http = response as? HTTPURLResponse else {
      throw ResolveError.networkUnavailable(repo)
    }
    switch http.statusCode {
    case 200...299: break
    case 401, 403: throw ResolveError.gated(repo)
    case 404: throw ResolveError.repoNotFound(repo)
    default:
      logger.error("HF API \(http.statusCode) for \(repo)")
      throw ResolveError.networkUnavailable(repo)
    }

    guard let decoded = try? JSONDecoder().decode(ModelInfoResponse.self, from: data),
      let siblings = decoded.siblings
    else {
      return []
    }
    return siblings
  }

  // MARK: - Selection

  /// Outcome of the main-file pick.
  private struct Pick {
    let rfilename: String  // repo-relative path
    let quant: String  // canonical label
  }

  private static func selectMain(
    repo: String, requestedQuant: String?,
    siblings: [Sibling], budgetMb: Double
  ) throws -> Pick {
    let allGgufs = siblings.filter { isGgufCandidate($0.rfilename) }
    guard !allGgufs.isEmpty else { throw ResolveError.noGgufFiles(repo) }

    // 1. Explicit quant: match any sibling whose parsed label == requested.
    if let requested = requestedQuant {
      let matches = allGgufs.filter { sib in
        guard let label = GGUFQuantLabel.parse(sib.rfilename) else { return false }
        return GGUFQuantLabel.matches(label, requested)
      }
      guard let picked = largest(matches, siblings: siblings, repo: repo) else {
        throw ResolveError.quantNotFound(repo: repo, quant: requested)
      }
      if matches.count > 1 {
        logger.info(
          "Ambiguous quant \(requested) in \(repo): \(matches.count) matches; picked largest")
      }
      // The picked sibling's parsed label is the canonical quant — we ran it
      // through the same grammar the post-download sideloaded scan uses, so
      // the resulting `{org}/{repo}:{QUANT}` id round-trips exactly.
      let canonical = GGUFQuantLabel.parse(picked.rfilename) ?? requested.uppercased()
      return Pick(
        rfilename: picked.rfilename,
        quant: canonical)
    }

    // 2. No quant: mirror llama.cpp's `find_best_model`
    // (`common/download.cpp:623`) — try Q4_K_M tag, then Q4_0 tag, else fall
    // back to the largest fits-budget candidate. Skip imatrix/mmproj/split-
    // shard-continuations — we only want standalone mains or the first shard
    // of a sharded set. For sharded quants, compatibility uses the sum of all
    // shard sizes when HF provided per-shard sizes; otherwise we fall back to
    // the first shard's size.
    let selectable = allGgufs.filter { sib in
      let name = (sib.rfilename as NSString).lastPathComponent
      if name.lowercased().hasPrefix("mmproj") { return false }
      if name.lowercased().contains("imatrix") { return false }
      if HFRepoParser.isSplitShard(name) && !HFRepoParser.isFirstShard(name) { return false }
      return true
    }
    guard !selectable.isEmpty else { throw ResolveError.noGgufFiles(repo) }

    let compatible = selectable.filter {
      Model.estimatedWeightFits(
        bytes: estimatedModelBytes(for: $0, siblings: siblings, repo: repo), budgetMb: budgetMb)
    }

    // Tag preference: try each in order, take the first matching candidate.
    // The boundary `[.-]` mirrors llama.cpp's regex exactly, so e.g.
    // `UD-Q4_K_XL.gguf` doesn't get treated as Q4_K_M.
    let preferred: Sibling? = ["Q4_K_M", "Q4_0"].lazy.compactMap { tag in
      compatible.first { sib in
        sib.rfilename.range(
          of: "\(tag)[.-]",
          options: [.regularExpression, .caseInsensitive]) != nil
      }
    }.first

    // Fallback: largest fits-budget candidate. We deviate from llama.cpp's
    // "first listed" (alphabetical) here — alphabetical fallback systematically
    // picks BF16/F16 over smaller quants in repos that have them, which is
    // exactly the surprise we're trying to avoid.
    guard let best = preferred ?? largest(compatible, siblings: siblings, repo: repo) else {
      throw ResolveError.noCompatibleFile(repo: repo)
    }
    let label =
      GGUFQuantLabel.parse(best.rfilename)
      ?? HFRepoParser.parseQuant(filename: (best.rfilename as NSString).lastPathComponent)
      ?? "unknown"
    return Pick(
      rfilename: best.rfilename,
      quant: label.uppercased())
  }

  /// Picks the largest sibling from a list, ranking sharded variants by the
  /// sum of all shard sizes when available. Ties broken by rfilename for
  /// determinism. Returns nil for empty input.
  private static func largest(
    _ sibs: [Sibling], siblings: [Sibling], repo: String
  ) -> Sibling? {
    sibs.max { a, b in
      let aBytes = estimatedModelBytes(for: a, siblings: siblings, repo: repo) ?? 0
      let bBytes = estimatedModelBytes(for: b, siblings: siblings, repo: repo) ?? 0
      if aBytes != bBytes { return aBytes < bBytes }
      return a.rfilename < b.rfilename
    }
  }

  /// Estimated bytes for a runnable quant. If `main` is the first shard of a
  /// split model and all sibling sizes are known, returns the total across all
  /// shards; otherwise falls back to the main file's size.
  private static func estimatedModelBytes(
    for main: Sibling, siblings: [Sibling], repo: String
  ) -> Int64? {
    guard let shardPaths = try? expandShards(main: main.rfilename, siblings: siblings, repo: repo)
    else { return main.size }
    guard shardPaths.count > 1 else { return main.size }

    let sizeByPath = Dictionary(
      uniqueKeysWithValues: siblings.compactMap { sibling in
        sibling.size.map { (sibling.rfilename, $0) }
      })

    var total: Int64 = 0
    for path in shardPaths {
      guard let size = sizeByPath[path] else { return main.size }
      total += size
    }
    return total
  }

  // MARK: - Shard + mmproj expansion

  /// Returns the ordered list of shard filenames (including the main file) if
  /// `main` is part of a sharded set, else just `[main]`. Throws if any shard
  /// in the `1..M` range is missing.
  private static func expandShards(
    main: String, siblings: [Sibling], repo: String
  ) throws -> [String] {
    let basename = (main as NSString).lastPathComponent
    guard HFRepoParser.isSplitShard(basename) else { return [main] }

    // Parse the `-<N>-of-<M>.gguf` tail. Both shard indices are 5-digit zero-
    // padded, same as llama.cpp's sharder.
    let re = try NSRegularExpression(
      pattern: #"-(\d{5})-of-(\d{5})\.gguf$"#, options: .caseInsensitive)
    let range = NSRange(basename.startIndex..., in: basename)
    guard let m = re.firstMatch(in: basename, range: range),
      let mRange = Range(m.range(at: 2), in: basename),
      let total = Int(basename[mRange])
    else {
      return [main]
    }

    // `main` may be nested in a subdir — preserve the prefix when reconstructing siblings.
    let prefix: String = {
      if let slash = main.lastIndex(of: "/") {
        return String(main[..<main.index(after: slash)])
      }
      return ""
    }()

    // Template: strip `-NNNNN-of-NNNNN.gguf` (exactly what the regex matched
    // positionally) and rebuild with a varying index.
    let shardRange = Range(m.range, in: basename)!
    let stemBeforeShard = String(basename[..<shardRange.lowerBound])

    let siblingSet = Set(siblings.map(\.rfilename))
    var shards: [String] = []
    for i in 1...total {
      let idx = String(format: "%05d", i)
      let tot = String(format: "%05d", total)
      let shard = "\(stemBeforeShard)-\(idx)-of-\(tot).gguf"
      let full = prefix + shard
      guard siblingSet.contains(full) else {
        throw ResolveError.shardMissing(repo: repo, shard: shard)
      }
      shards.append(full)
    }
    return shards
  }

  /// Picks an mmproj sidecar: a lone `mmproj*.gguf` sibling, else nothing
  /// (logs when multiple candidates exist — picking silently would risk
  /// installing the wrong variant, e.g. F16 vs Q8, for vision).
  private static func pickMmproj(repo: String, siblings: [Sibling]) -> Sibling? {
    let candidates = siblings.filter { sib in
      let name = (sib.rfilename as NSString).lastPathComponent.lowercased()
      return name.hasPrefix("mmproj") && name.hasSuffix(".gguf")
    }
    guard !candidates.isEmpty else { return nil }

    if candidates.count == 1 { return candidates[0] }

    logger.info("Multiple mmproj candidates in \(repo); skipping attach.")
    return nil
  }

  // MARK: - Helpers

  private static func isGgufCandidate(_ path: String) -> Bool {
    path.lowercased().hasSuffix(".gguf")
  }

  private static func resolveUrl(repo: String, path: String) -> URL {
    // Encode each path segment separately so `/` stays a delimiter.
    let encodedPath =
      path
      .split(separator: "/", omittingEmptySubsequences: false)
      .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
      .joined(separator: "/")
    return URL(string: "https://huggingface.co/\(repo)/resolve/main/\(encodedPath)")!
  }
}
