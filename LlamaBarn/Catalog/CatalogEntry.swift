import Foundation

/// Represents a complete AI model configuration with metadata and file locations
struct CatalogEntry: Identifiable, Codable {
  let id: String  // Unique identifier for the model
  let family: String  // Model family name (e.g., "Qwen 3", "Gemma 3n")
  let size: String  // Model size (e.g., "8B", "E4B")
  let releaseDate: Date  // Model release date
  let ctxWindow: Int  // Maximum context window in tokens
  let fileSize: Int64  // File size in bytes for progress tracking and display
  /// Estimated KV-cache footprint for a 1k-token context, in bytes.
  /// This helps us preflight memory requirements before launching llama-server.
  let ctxBytesPer1kTokens: Int
  /// Overhead multiplier for the model file size (e.g., 1.3 = 30% overhead).
  /// Applied during memory calculations to account for loading overhead.
  let overheadMultiplier: Double
  let downloadUrl: URL  // Remote download URL
  /// Optional additional model shards. When present, the first shard in `downloadUrl`
  /// should be passed to `--model` and llama-server will discover the rest in the same directory.
  let additionalParts: [URL]?
  let serverArgs: [String]  // Additional command line arguments for llama-server
  let icon: String  // Asset name for the model's brand logo
  let color: String  // Hex color for the model family (e.g., "#3e2c61")
  let quantization: String  // Quantization method (e.g., "Q4_K_M", "Q8_0")
  let isFullPrecision: Bool

  init(
    id: String,
    family: String,
    size: String,
    releaseDate: Date,
    ctxWindow: Int,
    fileSize: Int64,
    ctxBytesPer1kTokens: Int,
    overheadMultiplier: Double = 1.05,
    downloadUrl: URL,
    additionalParts: [URL]? = nil,
    serverArgs: [String],
    icon: String,
    color: String,
    quantization: String,
    isFullPrecision: Bool
  ) {
    self.id = id
    self.family = family
    self.size = size
    self.releaseDate = releaseDate
    self.ctxWindow = ctxWindow
    self.fileSize = fileSize
    self.ctxBytesPer1kTokens = ctxBytesPer1kTokens
    self.overheadMultiplier = overheadMultiplier
    self.downloadUrl = downloadUrl
    self.additionalParts = additionalParts
    self.serverArgs = serverArgs
    self.icon = icon
    self.color = color
    self.quantization = quantization
    self.isFullPrecision = isFullPrecision
  }

  /// Display name combining family and size
  var displayName: String {
    "\(family) \(size)"
  }

  /// Full name including quantization suffix (e.g., "Gemma 3 27B-Q4")
  var fullName: String {
    var name = displayName
    if !isFullPrecision,
      let quantLabel = QuantizationFormatters.short(quantization).nilIfEmpty
    {
      name += "-\(quantLabel)"
    }
    return name
  }

  /// Size label with quantization suffix (e.g., "27B" or "27B-Q4")
  var sizeLabel: String {
    guard !isFullPrecision,
      let quantLabel = QuantizationFormatters.short(quantization).nilIfEmpty
    else {
      return size
    }
    return "\(size)-\(quantLabel)"
  }

  // Removed: isSlidingWindowFamily; models that should run with max context include "-c 0" in serverArgs.

  /// Total size including all model files
  var totalSize: String {
    ByteFormatters.gbOneDecimal(fileSize)
  }

  /// Simplified quantization display (e.g., "Q4" from "Q4_K_M")
  var simplifiedQuantization: String {
    String(quantization.prefix(2))
  }

  /// Estimated runtime memory (in MB) when running at the model's maximum context window.
  var estimatedRuntimeMemoryMbAtMaxContext: UInt64 {
    let maxTokens =
      ctxWindow > 0
      ? Double(ctxWindow)
      : Catalog.compatibilityCtxWindowTokens
    return Catalog.runtimeMemoryUsageMb(
      for: self, ctxWindowTokens: maxTokens)
  }

  /// The local file system path where the model file will be stored
  var modelFilePath: String {
    Self.modelStorageDirectory.appendingPathComponent(downloadUrl.lastPathComponent).path
  }

  /// All local file paths this model requires (main file + shards if any)
  var allLocalModelPaths: [String] {
    let baseDir = URL(fileURLWithPath: modelFilePath).deletingLastPathComponent()
    var paths = [modelFilePath]
    if let additional = additionalParts {
      for url in additional {
        paths.append(baseDir.appendingPathComponent(url.lastPathComponent).path)
      }
    }
    return paths
  }

  // Removed: visionFile and related local path; multimodal files are not tracked.

  /// The directory where AI models are stored, creating it if necessary
  static var modelStorageDirectory: URL {
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    let modelsDirectory = homeDirectory.appendingPathComponent(".llamabarn", isDirectory: true)

    if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
      do {
        try FileManager.default.createDirectory(
          at: modelsDirectory, withIntermediateDirectories: true)
      } catch {
        print("Error creating ~/.llamabarn directory: \(error)")
      }
    }

    return modelsDirectory
  }
}
