import Foundation

/// Represents a complete AI model configuration with metadata and file locations
struct ModelCatalogEntry: Identifiable, Codable {
  let id: String  // Unique identifier for the model
  let family: String  // Model family name (e.g., "Qwen 3", "Gemma 3n")
  let variant: String  // Size/variant identifier (e.g., "8B", "E4B")
  let releaseDate: Date  // Model release date
  let contextLength: Int  // Maximum context length in tokens
  let fileSize: Int64  // File size in bytes for progress tracking and display
  /// Estimated KV-cache footprint for a 1k-token context, in bytes.
  /// This helps us preflight memory requirements before launching llama-server.
  let ctxFootprint: Int
  let downloadUrl: URL  // Remote download URL
  /// Optional additional model shards. When present, the first shard in `downloadUrl`
  /// should be passed to `--model` and llama-server will discover the rest in the same directory.
  let additionalParts: [URL]?
  let serverArgs: [String]  // Additional command line arguments for llama-server
  let icon: String  // Asset name for the model's brand logo
  let quantization: String  // Quantization method (e.g., "Q4_K_M", "Q8_0")
  let isFullPrecision: Bool

  init(
    id: String,
    family: String,
    variant: String,
    releaseDate: Date,
    contextLength: Int,
    fileSize: Int64,
    ctxFootprint: Int,
    downloadUrl: URL,
    additionalParts: [URL]? = nil,
    serverArgs: [String],
    icon: String,
    quantization: String,
    isFullPrecision: Bool
  ) {
    self.id = id
    self.family = family
    self.variant = variant
    self.releaseDate = releaseDate
    self.contextLength = contextLength
    self.fileSize = fileSize
    self.ctxFootprint = ctxFootprint
    self.downloadUrl = downloadUrl
    self.additionalParts = additionalParts
    self.serverArgs = serverArgs
    self.icon = icon
    self.quantization = quantization
    self.isFullPrecision = isFullPrecision
  }

  /// Display name combining family and variant
  var displayName: String {
    "\(family) \(variant)"
  }

  // Removed: isSlidingWindowFamily; models that should run with max context include "-c 0" in serverArgs.

  /// Total size including all model files
  var totalSize: String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB]
    formatter.countStyle = .decimal
    return formatter.string(fromByteCount: fileSize)
  }

  /// Simplified quantization display (e.g., "Q4" from "Q4_K_M")
  var simplifiedQuantization: String {
    String(quantization.prefix(2))
  }

  /// Estimated runtime memory (in MB) when running at the model's maximum context length.
  var estimatedRuntimeMemoryMBAtMaxContext: UInt64 {
    let maxTokens =
      contextLength > 0
      ? Double(contextLength)
      : ModelCatalog.compatibilityContextLengthTokens
    return ModelCatalog.runtimeMemoryUsageMB(
      for: self, contextLengthTokens: maxTokens)
  }

  /// The local file system path where the model file will be stored
  var modelFilePath: String {
    Self.getModelStorageDirectory().appendingPathComponent(downloadUrl.lastPathComponent).path
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

  /// Returns the directory where AI models are stored, creating it if necessary
  static func getModelStorageDirectory() -> URL {
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
