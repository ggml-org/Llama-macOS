import Foundation

/// Represents a complete AI model configuration with metadata and file locations.
/// Used for both curated catalog models and sideloaded models discovered in the HF cache.
struct CatalogEntry: Identifiable {
  let id: String  // Unique identifier for the model
  let family: String  // Model family name (e.g., "Qwen3", "Gemma 3n")
  let parameterCount: Int64  // Total model parameters (from HF API)
  let size: String  // Model size (e.g., "8B", "E4B")
  let ctxWindow: Int  // Maximum context length in tokens
  let fileSize: Int64  // File size in bytes for progress tracking and display
  /// Estimated KV-cache footprint for a 1k-token context, in bytes.
  /// This helps us preflight memory requirements before launching llama-server.
  /// For sideloaded models, starts at 0 and is updated async by llama-fit-params.
  var ctxBytesPer1kTokens: Int
  /// Measured resident weight memory in bytes, from llama-fit-params.
  /// 0 means unavailable — compatibility math falls back to fileSize * overheadMultiplier.
  /// Only populated for sideloaded models (catalog models are evaluated pre-download).
  /// For MoE models this is much smaller than fileSize, since only active experts
  /// contribute to resident memory.
  var fitResidentBytes: Int
  /// Overhead multiplier for the model file size (e.g., 1.3 = 30% overhead).
  /// Applied during memory calculations to account for loading overhead.
  let overheadMultiplier: Double
  let downloadUrl: URL  // Remote download URL
  /// Optional additional files required by the model:
  /// - Vision models: mmproj file for multimodal projection
  /// - Multi-part models: additional shards (e.g., 00002-of-00003.gguf)
  /// The main model file in `downloadUrl` is passed to `--model`; llama-server discovers these in the same directory.
  let additionalParts: [URL]?
  let mmprojUrl: URL?
  /// Override for the local filename of the mmproj file.
  /// When set, the mmproj will be saved/referenced with this name instead of the URL's last path component.
  let mmprojLocalFilename: String?
  let serverArgs: [String]  // Additional command line arguments for llama-server
  let icon: String  // Asset name for the model's brand logo
  let quantization: String  // Quantization method (e.g., "Q4_K_M", "Q8_0")
  let isFullPrecision: Bool

  // MARK: - Sideloaded Model Properties

  /// True for models discovered in the HF cache that don't match any catalog entry.
  /// Sideloaded models have less metadata and get memory estimates via llama-fit-params.
  let isSideloaded: Bool

  /// HF org for sideloaded models (e.g. "bartowski"). Nil for catalog models.
  /// Always shown for sideloaded models to avoid ambiguity.
  let org: String?

  /// Additional tags parsed from the repo name (e.g. ["Instruct", "it"]).
  /// Excludes GGUF/GGML. Empty for catalog models.
  let tags: [String]

  init(
    id: String,
    family: String,
    parameterCount: Int64,
    size: String,
    ctxWindow: Int,
    fileSize: Int64,
    ctxBytesPer1kTokens: Int,
    fitResidentBytes: Int = 0,
    overheadMultiplier: Double = 1.05,
    downloadUrl: URL,
    additionalParts: [URL]? = nil,
    mmprojUrl: URL? = nil,
    mmprojLocalFilename: String? = nil,
    serverArgs: [String],
    icon: String,
    quantization: String,
    isFullPrecision: Bool,
    isSideloaded: Bool = false,
    org: String? = nil,
    tags: [String] = []
  ) {
    self.id = id
    self.family = family
    self.parameterCount = parameterCount
    self.size = size
    self.ctxWindow = ctxWindow
    self.fileSize = fileSize
    self.ctxBytesPer1kTokens = ctxBytesPer1kTokens
    self.fitResidentBytes = fitResidentBytes
    self.overheadMultiplier = overheadMultiplier
    self.downloadUrl = downloadUrl
    self.additionalParts = additionalParts
    self.mmprojUrl = mmprojUrl
    self.mmprojLocalFilename = mmprojLocalFilename
    self.serverArgs = serverArgs
    self.icon = icon
    self.quantization = quantization
    self.isFullPrecision = isFullPrecision
    self.isSideloaded = isSideloaded
    self.org = org
    self.tags = tags
  }

  /// Display name combining family and size
  var displayName: String {
    "\(family) \(size)"
  }

  /// Size label (e.g., "27B")
  var sizeLabel: String {
    size
  }

  /// Quantization label (e.g., "Q4") - nil if full precision or empty
  var quantizationLabel: String? {
    guard !isFullPrecision else { return nil }
    let label = Format.quantization(quantization)
    return label.isEmpty ? nil : label
  }

  /// Total size including all model files
  var totalSize: String {
    Format.gigabytes(fileSize)
  }

  /// Whether the model supports vision/multimodal capabilities
  var hasVisionSupport: Bool {
    mmprojUrl != nil
  }

  /// Estimated runtime memory (in MB) when running at the model's maximum context length.
  var estimatedRuntimeMemoryMbAtMaxContext: UInt64 {
    let maxTokens =
      ctxWindow > 0
      ? Double(ctxWindow)
      : Self.compatibilityCtxWindowTokens
    return runtimeMemoryUsageMb(ctxWindowTokens: maxTokens)
  }

  /// The legacy flat-directory path for the model file (~/.llamabarn/{filename}).
  /// Used for backward compat scanning of pre-HF-cache installs.
  var legacyModelFilePath: String {
    Self.legacyStorageDir.appendingPathComponent(downloadUrl.lastPathComponent).path
  }

  /// The URL to the model's page on Hugging Face
  var huggingFaceUrl: URL {
    // Assuming downloadUrl is like https://huggingface.co/{user}/{repo}/...
    let components = downloadUrl.pathComponents
    if components.count >= 3 {
      let user = components[1]
      let repo = components[2]
      if let url = URL(string: "https://huggingface.co/\(user)/\(repo)") {
        return url
      }
    }
    // Fallback to the root of the download URL if parsing fails
    return downloadUrl.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  /// The legacy flat-directory path for the mmproj file, if applicable.
  /// Uses mmprojLocalFilename override to prevent collisions in the flat directory.
  var legacyMmprojFilePath: String? {
    guard let mmprojUrl = mmprojUrl else { return nil }
    let filename = mmprojLocalFilename ?? mmprojUrl.lastPathComponent
    return Self.legacyStorageDir.appendingPathComponent(filename).path
  }

  /// Returns the local filename that should be used for a given remote download URL.
  /// Handles mmproj filename overrides to prevent collisions in the flat cache directory.
  func localFilename(for remoteUrl: URL) -> String {
    if let mmprojUrl = mmprojUrl, remoteUrl == mmprojUrl, let override = mmprojLocalFilename {
      return override
    }
    return remoteUrl.lastPathComponent
  }

  /// All legacy flat-directory paths this model requires (main + shards + mmproj).
  var legacyLocalPaths: [String] {
    let baseDir = URL(fileURLWithPath: legacyModelFilePath).deletingLastPathComponent()
    var paths = [legacyModelFilePath]
    if let additional = additionalParts {
      for url in additional {
        paths.append(baseDir.appendingPathComponent(url.lastPathComponent).path)
      }
    }
    if let mmprojPath = legacyMmprojFilePath {
      paths.append(mmprojPath)
    }
    return paths
  }

  /// All remote URLs this model requires (main file + additional parts + mmproj)
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

  /// The legacy flat directory for models (~/.llamabarn/).
  /// Used for backward compat scanning and as llama-server working directory.
  static var legacyStorageDir: URL {
    UserSettings.legacyModelDir
  }

  /// The HF cache repo directory name for this model (e.g. "models--unsloth--Qwen3.5-2B-GGUF").
  /// Derived from the download URL. Returns nil for non-HF URLs.
  var hfRepoDir: String? {
    HFCache.repoDirName(from: downloadUrl)
  }

  /// Groups models by family, then by model size (e.g., 2B, 4B), then full-precision before quantized variants.
  /// Sideloaded models sort after catalog models so curated entries appear first.
  /// Used for both installed and available models lists to keep related models together.
  static func displayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    // Catalog models before sideloaded
    if lhs.isSideloaded != rhs.isSideloaded { return !lhs.isSideloaded }
    if lhs.family != rhs.family { return lhs.family < rhs.family }
    if lhs.parameterCount != rhs.parameterCount { return lhs.parameterCount < rhs.parameterCount }
    if lhs.isFullPrecision != rhs.isFullPrecision { return lhs.isFullPrecision }
    return lhs.id < rhs.id
  }
}
