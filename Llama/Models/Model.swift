import Foundation

/// Represents an installed or installable AI model.
/// Built from a deeplink resolve (placeholder pre-download) or from the HF
/// cache scan (post-install). Metadata is parsed from the HF repo dir name and
/// the GGUF filename — there is no curated catalog backing this struct.
struct Model: Identifiable, Codable {
  /// Stable model id built by `makeId` — the verbatim `{org}/{repo}:{TAG}`,
  /// exactly llama-server's `-hf` shorthand, for every org. Stable across the
  /// deeplink and post-install scan paths because both derive the tag through
  /// `GGUFQuant.tag(forPath:)` and build the id through `makeId`.
  let id: String
  /// Family name parsed from the repo (e.g. "Qwen3-30B-A3B-Instruct"). Not
  /// displayed (rows show the id) — drives brand-logo matching and sort order.
  let family: String
  /// Maximum context length in tokens. 128k upper bound — clamped by the
  /// memory budget once `ctxBytesPer1kTokens` is measured.
  let ctxWindow: Int
  /// Total bytes on disk for the model (main + shards + mmproj).
  let fileSize: Int64
  /// Estimated KV-cache footprint for a 1k-token context, in bytes.
  /// 0 = MemProfile probe is pending; -1 = probe failed; >0 = measured.
  var ctxBytesPer1kTokens: Int
  /// Measured resident weight memory in bytes from the MemProfile probe.
  /// 0 means unavailable — compatibility math falls back to
  /// `fileSize * overheadMultiplier`. For MoE models this is much smaller than
  /// `fileSize`, since only active experts contribute to resident memory.
  var residentBytes: Int
  /// Remote main GGUF URL — used by the deeplink download path. Sideloaded
  /// scan-discovered entries set this to `file:///` since no remote URL is
  /// needed once files are on disk.
  let downloadUrl: URL
  /// Additional shard URLs for multi-part GGUFs (00002-of-00003.gguf etc.).
  /// `llama-server` discovers these in the same directory as the main file.
  let additionalParts: [URL]?
  /// Vision projection sidecar URL (mmproj.gguf). Pre-download placeholders
  /// from the deeplink path carry this when the resolver attaches one.
  let mmprojUrl: URL?
  /// MTP draft-head sidecar URL (`mtp-….gguf`). Some repos ship a separate
  /// multi-token-prediction head alongside the main weights; when present we
  /// download it and hand it to llama-server as the speculative draft model.
  /// Pre-download placeholders carry this when the resolver attaches one.
  let mtpUrl: URL?
  /// HF org parsed from the repo dir (e.g. "bartowski"). Shown in the row to
  /// disambiguate repos that share a base name across orgs.
  let org: String

  init(
    id: String,
    family: String,
    ctxWindow: Int = 131_072,
    fileSize: Int64,
    ctxBytesPer1kTokens: Int = 0,
    residentBytes: Int = 0,
    downloadUrl: URL,
    additionalParts: [URL]? = nil,
    mmprojUrl: URL? = nil,
    mtpUrl: URL? = nil,
    org: String
  ) {
    self.id = id
    self.family = family
    self.ctxWindow = ctxWindow
    self.fileSize = fileSize
    self.ctxBytesPer1kTokens = ctxBytesPer1kTokens
    self.residentBytes = residentBytes
    self.downloadUrl = downloadUrl
    self.additionalParts = additionalParts
    self.mmprojUrl = mmprojUrl
    self.mtpUrl = mtpUrl
    self.org = org
  }

  /// Builds the stable model id shared by the deeplink and post-install scan
  /// paths: the verbatim `{org}/{repo}:{TAG}`, matching llama-server's `-hf`
  /// shorthand for every org — no lowercasing, no `-GGUF` stripping, no org
  /// dropped. One grammar means every id round-trips through `-hf` and matches
  /// llama-server's own cache-scan naming; row-length concerns are handled by
  /// the display layer (`ModelIdParser`), not the id.
  static func makeId(org: String, repo: String, tag: String) -> String {
    "\(idBase(org: org, repo: repo)):\(tag)"
  }

  /// `makeId` for a combined `{org}/{repo}` string, as deeplinks carry it.
  static func makeId(orgSlashRepo: String, tag: String) -> String {
    "\(idBase(orgSlashRepo: orgSlashRepo)):\(tag)"
  }

  /// The pre-colon portion of the id for a given org/repo. Lets callers that
  /// hold a catalog repo string (`{org}/{repo}`) match against installed model
  /// ids regardless of quant — e.g. the Discover section hiding suggestions
  /// whose repo is already installed.
  static func idBase(org: String, repo: String) -> String {
    "\(org)/\(repo)"
  }

  /// `idBase` for a combined `{org}/{repo}` string, as catalog suggestions
  /// carry it. The id base is the repo string verbatim.
  static func idBase(orgSlashRepo: String) -> String {
    orgSlashRepo
  }

  /// The pre-colon portion of this model's id (e.g.
  /// "unsloth/GLM-4.7-Flash-GGUF"). Hints, alerts, and logs show it raw; menu
  /// rows render a parsed view of the id (`ModelIdParser`) — a deterministic
  /// rendering, not a second name, so every surface still derives from the
  /// one id string.
  var idBase: String {
    guard let colonIdx = id.lastIndex(of: ":") else { return id }
    return String(id[..<colonIdx])
  }

  /// Display name — the id base. Kept as a semantic alias so call sites read
  /// as "the model's name" rather than "an id fragment".
  var displayName: String {
    idBase
  }

  /// Brand logo asset name in `Assets.xcassets/ModelLogos`, matched from the
  /// parsed family name. Nil when the family doesn't match a known brand — the
  /// row then falls back to a generic system symbol.
  var brandLogoAsset: String? {
    ModelLogos.asset(matching: family)
  }

  /// Human-readable total file size for the metadata line.
  var totalSize: String {
    Format.gigabytes(fileSize)
  }

  /// Vision support is implied by an attached mmproj sidecar.
  var hasVisionSupport: Bool {
    mmprojUrl != nil
  }

  /// All remote URLs this model needs to download (main + shards + mmproj).
  var allDownloadUrls: [URL] {
    var urls = [downloadUrl]
    if let additional = additionalParts {
      urls.append(contentsOf: additional)
    }
    if let mmproj = mmprojUrl {
      urls.append(mmproj)
    }
    if let mtp = mtpUrl {
      urls.append(mtp)
    }
    return urls
  }

  /// HF cache repo directory name (e.g. "models--unsloth--Qwen3.5-2B-GGUF").
  /// Derived from `downloadUrl` for placeholder rows that came from a deeplink.
  /// Nil for scan-discovered entries (whose `downloadUrl` is `file:///`); those
  /// carry the dir name in `ResolvedPaths.hfRepoDirName` instead.
  var hfRepoDir: String? {
    HFCache.repoDirName(from: downloadUrl)
  }

  /// Sort key — mirrors the row's rendering: non-default orgs keep their
  /// `org/` prefix (see `ModelIdParser.Parsed.displayOrg`), so prefixed rows
  /// sort by the org and cluster together, and the list's left edge stays
  /// alphabetical. Default-org models key on the bare family, matching their
  /// bare rendering. (The name part is `family`, the historical sort key —
  /// close to the parsed name a row shows, not character-identical.)
  private var sortKey: String {
    if let org = ModelIdParser.parse(id).displayOrg {
      return "\(org)/\(family)"
    }
    return family
  }

  /// Sort order — by displayed name, then by id for stability. Parameter
  /// counts and full-precision rankings are no longer available without a
  /// curated catalog, so id is the tie-breaker.
  static func displayOrder(_ lhs: Model, _ rhs: Model) -> Bool {
    // Keys are compared case-insensitively so differently-cased families
    // (e.g. "gemma-4", "embeddinggemma") sort alongside their capitalized
    // siblings rather than clustering at the end of the list. Ties (same
    // key ignoring case) fall back to the id for a stable order.
    let keyOrder = lhs.sortKey.caseInsensitiveCompare(rhs.sortKey)
    if keyOrder != .orderedSame { return keyOrder == .orderedAscending }
    return lhs.id < rhs.id
  }
}
