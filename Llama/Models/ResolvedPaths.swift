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
  /// Whether the main GGUF carries an *embedded* multi-token-prediction (MTP)
  /// head. When true we hand llama-server `spec-type = draft-mtp` so it uses
  /// the head for speculative decoding (a free ~2x on the MoE families that
  /// ship it). Detected from the filename -- these builds tag themselves with
  /// an `mtp` token (e.g. `…-Q4_K_M-mtp.gguf`, `…-MTP-Q8_0.gguf`).
  let usesMTP: Bool
  /// Absolute path to a *sidecar* MTP draft head (`mtp-….gguf`) shipped beside
  /// the main weights, nil when absent. When set we pass it to llama-server as
  /// `spec-draft-model` alongside `spec-type = draft-mtp`. Takes precedence over
  /// `usesMTP` (a model has one form or the other, not both).
  let mtpSidecarFile: String?
  /// HF cache repo directory name (e.g. "models--bartowski--Llama-3.2-1B-Instruct-GGUF").
  /// Used by deletion to clean up the per-repo directory tree.
  let hfRepoDirName: String

  init(
    modelFile: String,
    additionalParts: [String],
    mmprojFile: String?,
    usesMTP: Bool = false,
    mtpSidecarFile: String? = nil,
    hfRepoDirName: String
  ) {
    self.modelFile = modelFile
    self.additionalParts = additionalParts
    self.mmprojFile = mmprojFile
    self.usesMTP = usesMTP
    self.mtpSidecarFile = mtpSidecarFile
    self.hfRepoDirName = hfRepoDirName
  }

  /// All file paths this model occupies on disk
  var allPaths: [String] {
    var paths = [modelFile]
    paths.append(contentsOf: additionalParts)
    if let mmproj = mmprojFile {
      paths.append(mmproj)
    }
    if let mtp = mtpSidecarFile {
      paths.append(mtp)
    }
    return paths
  }
}
