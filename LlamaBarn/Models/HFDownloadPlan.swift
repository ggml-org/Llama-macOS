import Foundation

/// Metadata gathered from the HF API before starting a download.
/// Provides the information needed to write files into the HF cache layout.
struct HFDownloadPlan {
  /// HF cache repo directory name (e.g. "models--unsloth--Qwen3.5-2B-GGUF")
  let repoDir: String
  /// Git commit hash for the snapshot directory
  let commit: String
  /// Maps each remote download URL to its content SHA256 hash (blob name).
  /// URLs whose hash couldn't be obtained from the API are absent —
  /// their hash must be computed after download.
  var blobHashes: [URL: String]
}
