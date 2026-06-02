import Foundation

/// Represents an installed or installable AI model.
/// Built from a deeplink resolve (placeholder pre-download) or from the HF
/// cache scan (post-install). Metadata is parsed from the HF repo dir name and
/// the GGUF filename — there is no curated catalog backing this struct.
struct Model: Identifiable {
  /// `{org}/{repo}:{QUANT}` — matches llama-server's `-hf` shorthand. Stable
  /// across the deeplink and post-install scan paths because both derive the
  /// quant label through the same `GGUFQuantLabel` grammar.
  let id: String
  /// Display family name parsed from the repo (e.g. "Qwen3-30B-A3B-Instruct").
  let family: String
  /// Display size label — parsed parameter count (e.g. "30B") or, if the repo
  /// name doesn't carry one, the quant label as a fallback. Distinct from the
  /// numeric `fileSize`: this is the human-facing parameter-size string.
  let sizeLabel: String
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
  /// HF org parsed from the repo dir (e.g. "bartowski"). Shown in the row to
  /// disambiguate repos that share a base name across orgs.
  let org: String
  /// Extra tags parsed from the repo name (e.g. ["Instruct", "it"]).
  /// Excludes GGUF/GGML.
  let tags: [String]
  /// Quantization label (e.g. "Q4_K_M", "Q8_0", "F16"). Part of the id.
  let quantization: String

  init(
    id: String,
    family: String,
    sizeLabel: String,
    ctxWindow: Int = 131_072,
    fileSize: Int64,
    ctxBytesPer1kTokens: Int = 0,
    residentBytes: Int = 0,
    overheadMultiplier: Double = 1.05,
    downloadUrl: URL,
    additionalParts: [URL]? = nil,
    mmprojUrl: URL? = nil,
    org: String,
    tags: [String] = [],
    quantization: String
  ) {
    self.id = id
    self.family = family
    self.sizeLabel = sizeLabel
    self.ctxWindow = ctxWindow
    self.fileSize = fileSize
    self.ctxBytesPer1kTokens = ctxBytesPer1kTokens
    self.residentBytes = residentBytes
    self.overheadMultiplier = overheadMultiplier
    self.downloadUrl = downloadUrl
    self.additionalParts = additionalParts
    self.mmprojUrl = mmprojUrl
    self.org = org
    self.tags = tags
    self.quantization = quantization
  }

  /// Display name combining family and size — used in hints, alerts, logs.
  var displayName: String {
    "\(family) \(sizeLabel)"
  }

  /// Brand logo asset name in `Assets.xcassets/ModelLogos`, matched from the
  /// parsed family name. Nil when the family doesn't match a known brand — the
  /// row then falls back to a generic system symbol. Without a curated catalog
  /// the brand is inferred by keyword rather than looked up.
  var brandLogoAsset: String? {
    let haystack = family.lowercased()
    // Keyword → logo asset. Several Mistral lines share one mark; GLM is z.ai's;
    // Nemotron is NVIDIA's. Order only matters where keywords overlap (none do).
    let brands: [(keyword: String, asset: String)] = [
      ("qwen", "qwen"),
      ("gemma", "gemma"),
      ("gpt", "gpt"),
      ("mistral", "mistral"),
      ("ministral", "mistral"),
      ("devstral", "mistral"),
      ("magistral", "mistral"),
      ("glm", "z"),
      ("nemotron", "nvidia"),
    ]
    guard let asset = brands.first(where: { haystack.contains($0.keyword) })?.asset
    else { return nil }
    return "ModelLogos/\(asset)"
  }

  /// Pretty quantization label (e.g. "Q4") for the row subtitle.
  /// Nil when the label maps to "no qualifier needed" (full precision, empty).
  var quantizationLabel: String? {
    let label = Format.quantization(quantization)
    return label.isEmpty ? nil : label
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
    if lhs.family != rhs.family { return lhs.family < rhs.family }
    return lhs.id < rhs.id
  }
}
