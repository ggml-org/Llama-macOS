import Foundation

/// Resolved file paths for a downloaded model.
/// Separates "what is this model" (`Model`) from "where is it on disk".
struct ResolvedPaths {
  /// Absolute path to the main model file
  let modelFile: String
  /// Absolute paths to additional shard files (multi-part models)
  let additionalParts: [String]
  /// Absolute path to the mmproj file (vision models), nil if not applicable
  let mmprojFile: String?
  /// HF cache repo directory name (e.g. "models--bartowski--Llama-3.2-1B-Instruct-GGUF").
  /// Used by deletion to clean up the per-repo directory tree.
  let hfRepoDirName: String

  init(
    modelFile: String,
    additionalParts: [String],
    mmprojFile: String?,
    hfRepoDirName: String
  ) {
    self.modelFile = modelFile
    self.additionalParts = additionalParts
    self.mmprojFile = mmprojFile
    self.hfRepoDirName = hfRepoDirName
  }

  /// All file paths this model occupies on disk
  var allPaths: [String] {
    var paths = [modelFile]
    paths.append(contentsOf: additionalParts)
    if let mmproj = mmprojFile {
      paths.append(mmproj)
    }
    return paths
  }
}
