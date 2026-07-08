import Foundation

/// Represents an installed or installable AI model.
/// Built from a deeplink resolve (placeholder pre-download) or from the HF
/// cache scan (post-install). Metadata is parsed from the HF repo dir name and
/// the GGUF filename — there is no curated catalog backing this struct.
struct Model: Identifiable, Codable {
  /// Stable model id built by `makeId` — `{org}/{repo}:{QUANT}` (matching
  /// llama-server's `-hf` shorthand), or a short slashless form for native
  /// (ggml-org) models. Stable across the deeplink and post-install scan paths
  /// because both derive the quant label through the same `GGUFQuantLabel`
  /// grammar and build the id through `makeId`.
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
  /// Overhead multiplier for the model file size used when residentBytes is
  /// unavailable (e.g. pre-download placeholders). 1.05 = 5% overhead.
  let overheadMultiplier: Double
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
  /// Quantization label (e.g. "Q4_K_M", "Q8_0", "F16"). Part of the id.
  let quantization: String

  init(
    id: String,
    family: String,
    ctxWindow: Int = 131_072,
    fileSize: Int64,
    ctxBytesPer1kTokens: Int = 0,
    residentBytes: Int = 0,
    overheadMultiplier: Double = 1.05,
    downloadUrl: URL,
    additionalParts: [URL]? = nil,
    mmprojUrl: URL? = nil,
    mtpUrl: URL? = nil,
    org: String,
    quantization: String
  ) {
    self.id = id
    self.family = family
    self.ctxWindow = ctxWindow
    self.fileSize = fileSize
    self.ctxBytesPer1kTokens = ctxBytesPer1kTokens
    self.residentBytes = residentBytes
    self.overheadMultiplier = overheadMultiplier
    self.downloadUrl = downloadUrl
    self.additionalParts = additionalParts
    self.mmprojUrl = mmprojUrl
    self.mtpUrl = mtpUrl
    self.org = org
    self.quantization = quantization
  }

  /// The org whose models are native — ours, conceptually. Native models never
  /// expose the org concept to the user: no prefix in the id or the row.
  static let nativeOrg = "ggml-org"

  /// Builds the stable model id shared by the deeplink and post-install scan
  /// paths. Native models drop the org prefix and get a short, slashless id:
  /// lowercased repo name with the `-GGUF` suffix stripped
  /// (e.g. "qwen3-0.6b:Q8_0"). Models from any other org keep the
  /// `{org}/{repo}:{QUANT}` shape, which matches llama-server's `-hf`
  /// shorthand.
  static func makeId(org: String, repo: String, quant: String) -> String {
    "\(idBase(org: org, repo: repo)):\(quant)"
  }

  /// The pre-colon portion of the id for a given org/repo. Lets callers that
  /// hold a catalog repo string (`{org}/{repo}`) match against installed model
  /// ids regardless of quant — e.g. the Discover section hiding suggestions
  /// whose repo is already installed.
  static func idBase(org: String, repo: String) -> String {
    guard org == nativeOrg else { return "\(org)/\(repo)" }
    var base = repo
    if base.lowercased().hasSuffix("-gguf") {
      base = String(base.dropLast("-gguf".count))
    }
    return base.lowercased()
  }

  /// `idBase` for a combined `{org}/{repo}` string, as catalog suggestions
  /// carry it. Returns the input unchanged if there's no slash to split on.
  static func idBase(orgSlashRepo: String) -> String {
    guard let slashIdx = orgSlashRepo.firstIndex(of: "/") else { return orgSlashRepo }
    return idBase(
      org: String(orgSlashRepo[..<slashIdx]),
      repo: String(orgSlashRepo[orgSlashRepo.index(after: slashIdx)...])
    )
  }

  /// The pre-colon portion of this model's id (e.g. "gpt-oss-20b",
  /// "unsloth/GLM-4.7-Flash-GGUF"). The one display name — menu rows, hints,
  /// alerts, and logs all show the id, so every surface (including the WebUI,
  /// which renders the raw id from `/v1/models`) derives from the same string.
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

  /// Sort key — by family, then by id for stability. Parameter counts and
  /// full-precision rankings are no longer available without a curated
  /// catalog, so id is the tie-breaker.
  static func displayOrder(_ lhs: Model, _ rhs: Model) -> Bool {
    // Family is compared case-insensitively so differently-cased families
    // (e.g. "gemma-4", "embeddinggemma") sort alongside their capitalized
    // siblings rather than clustering at the end of the list. Ties (same
    // family ignoring case) fall back to the id for a stable order.
    let familyOrder = lhs.family.caseInsensitiveCompare(rhs.family)
    if familyOrder != .orderedSame { return familyOrder == .orderedAscending }
    return lhs.id < rhs.id
  }
}
