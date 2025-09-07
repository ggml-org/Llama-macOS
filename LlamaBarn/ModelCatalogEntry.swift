import Foundation

/// Represents a complete AI model configuration with metadata and file locations
struct ModelCatalogEntry: Identifiable, Codable {
  let id: String  // Unique identifier for the model
  let family: String  // Model family name (e.g., "Qwen 3", "Gemma 3n")
  let variant: String  // Size/variant identifier (e.g., "8B", "E4B")
  let sizeInBillions: Double  // Number of parameters in billions
  let releaseDate: Date  // Model release date
  let contextLength: Int  // Maximum context length in tokens
  let fileSizeMB: Int  // File size for progress tracking and display
  let downloadUrl: URL  // Remote download URL
  /// Optional additional model shards. When present, the first shard in `downloadUrl`
  /// should be passed to `--model` and llama-server will discover the rest in the same directory.
  let additionalParts: [URL]?
  let serverArgs: [String]  // Additional command line arguments for llama-server
  let icon: String  // Asset name for the model's brand logo
  let quantization: String  // Quantization method (e.g., "Q4_K_M", "Q8_0")

  init(
    id: String,
    family: String,
    variant: String,
    sizeInBillions: Double,
    releaseDate: Date,
    contextLength: Int,
    fileSizeMB: Int,
    downloadUrl: URL,
    additionalParts: [URL]? = nil,
    serverArgs: [String],
    icon: String,
    quantization: String
  ) {
    self.id = id
    self.family = family
    self.variant = variant
    self.sizeInBillions = sizeInBillions
    self.releaseDate = releaseDate
    self.contextLength = contextLength
    self.fileSizeMB = fileSizeMB
    self.downloadUrl = downloadUrl
    self.additionalParts = additionalParts
    self.serverArgs = serverArgs
    self.icon = icon
    self.quantization = quantization
  }

  /// Display name combining family and variant
  var displayName: String {
    "\(family) \(variant)"
  }

  /// Total size including all model files
  var totalSize: String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB]
    formatter.countStyle = .decimal
    let bytes = Int64(fileSizeMB * 1_000_000)
    return formatter.string(fromByteCount: bytes)
  }

  /// Simplified quantization display (e.g., "Q4" from "Q4_K_M")
  var simplifiedQuantization: String {
    String(quantization.prefix(2))
  }

  /// Check if all required files exist locally
  var isDownloaded: Bool {
    let modelFileExists = FileManager.default.fileExists(atPath: modelFilePath)
    let shardFilesExist: Bool = {
      guard let additional = additionalParts, !additional.isEmpty else { return true }
      let baseDir = URL(fileURLWithPath: modelFilePath).deletingLastPathComponent()
      for url in additional {
        let path = baseDir.appendingPathComponent(url.lastPathComponent).path
        if !FileManager.default.fileExists(atPath: path) { return false }
      }
      return true
    }()
    return modelFileExists && shardFilesExist
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
  private static func getModelStorageDirectory() -> URL {
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
