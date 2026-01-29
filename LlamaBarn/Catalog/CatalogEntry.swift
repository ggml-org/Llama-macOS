import Foundation

/// Represents a complete AI model configuration with metadata and file locations
struct CatalogEntry: Identifiable {
  let id: String  // Unique identifier for the model
  let family: String  // Model family name (e.g., "Qwen3", "Gemma 3n")
  let parameterCount: Int64  // Total model parameters (from HF API)
  let size: String  // Model size (e.g., "8B", "E4B")
  let ctxWindow: Int  // Maximum context length in tokens
  let fileSize: Int64  // File size in bytes for progress tracking and display
  /// Estimated KV-cache footprint for a 1k-token context, in bytes.
  /// This helps us preflight memory requirements before launching llama-server.
  let ctxBytesPer1kTokens: Int
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
  let serverArgs: [String]  // Additional command line arguments for llama-server
  let icon: String  // Asset name for the model's brand logo
  let quantization: String  // Quantization method (e.g., "Q4_K_M", "Q8_0")
  let isFullPrecision: Bool

  init(
    id: String,
    family: String,
    parameterCount: Int64,
    size: String,
    ctxWindow: Int,
    fileSize: Int64,
    ctxBytesPer1kTokens: Int,
    overheadMultiplier: Double = 1.05,
    downloadUrl: URL,
    additionalParts: [URL]? = nil,
    mmprojUrl: URL? = nil,
    serverArgs: [String],
    icon: String,
    quantization: String,
    isFullPrecision: Bool
  ) {
    self.id = id
    self.family = family
    self.parameterCount = parameterCount
    self.size = size
    self.ctxWindow = ctxWindow
    self.fileSize = fileSize
    self.ctxBytesPer1kTokens = ctxBytesPer1kTokens
    self.overheadMultiplier = overheadMultiplier
    self.downloadUrl = downloadUrl
    self.additionalParts = additionalParts
    self.mmprojUrl = mmprojUrl
    self.serverArgs = serverArgs
    self.icon = icon
    self.quantization = quantization
    self.isFullPrecision = isFullPrecision
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

  /// The local file system path where the model file will be stored
  var modelFilePath: String {
    Self.modelStorageDirectory.appendingPathComponent(downloadUrl.lastPathComponent).path
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

  /// The local file system path where the mmproj file will be stored, if applicable
  var mmprojFilePath: String? {
    guard let mmprojUrl = mmprojUrl else { return nil }
    return Self.modelStorageDirectory.appendingPathComponent(mmprojUrl.lastPathComponent).path
  }

  /// All local file paths this model requires (main file + additional parts like shards or mmproj files)
  var allLocalModelPaths: [String] {
    let baseDir = URL(fileURLWithPath: modelFilePath).deletingLastPathComponent()
    var paths = [modelFilePath]
    if let additional = additionalParts {
      for url in additional {
        paths.append(baseDir.appendingPathComponent(url.lastPathComponent).path)
      }
    }
    if let mmprojPath = mmprojFilePath {
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

  /// The directory where AI models are stored.
  /// Reads from UserSettings, which handles directory creation.
  static var modelStorageDirectory: URL {
    UserSettings.modelStorageDirectory
  }

  /// Groups models by family, then by model size (e.g., 2B, 4B), then full-precision before quantized variants.
  /// Used for both installed and available models lists to keep related models together.
  static func displayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    if lhs.family != rhs.family { return lhs.family < rhs.family }
    if lhs.parameterCount != rhs.parameterCount { return lhs.parameterCount < rhs.parameterCount }
    if lhs.isFullPrecision != rhs.isFullPrecision { return lhs.isFullPrecision }
    return lhs.id < rhs.id
  }
}
