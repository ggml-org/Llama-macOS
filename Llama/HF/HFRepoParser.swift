import Foundation

/// Parses HuggingFace repo directory names and GGUF filenames into structured
/// components. (Display parsing of a model's name, params and tags lives in
/// `ModelIdParser`, which works off the id and so covers every model alike.)
enum HFRepoParser {

  /// Splits a repo dir name (e.g. "models--bartowski--Llama-3.2-1B-Instruct-GGUF")
  /// into its org and repo. Returns nil if the format is unrecognized.
  static func parse(repoDir: String) -> (org: String, repo: String)? {
    // Extract org and repo from "models--{org}--{repo}"
    guard repoDir.hasPrefix("models--") else { return nil }

    // Split on "--" to get [models, org, repo]
    let dashDashParts = repoDir.components(separatedBy: "--")
    guard dashDashParts.count >= 3 else { return nil }

    let org = dashDashParts[1]
    let repo = dashDashParts[2...].joined(separator: "--")
    guard !org.isEmpty, !repo.isEmpty else { return nil }
    return (org, repo)
  }

  /// Extracts quantization from a GGUF filename.
  /// e.g. "Llama-3.2-1B-Instruct-Q4_K_M.gguf" → "Q4_K_M"
  /// e.g. "model-00001-of-00003.gguf" → nil (split shard, no quant in name)
  static func parseQuant(filename: String) -> String? {
    // Remove .gguf extension
    var base = filename
    if base.lowercased().hasSuffix(".gguf") {
      base = String(base.dropLast(5))
    }

    // For split shards, extract quant from the base name (before the shard suffix).
    // e.g. "Qwen3.5-122B-A10B-Q4_K_M-00001-of-00003.gguf" → base "Qwen3.5-122B-A10B-Q4_K_M"
    if isSplitShard(filename) {
      guard let shardBase = splitShardBaseName(filename) else { return nil }
      // Strip subdir prefix if present (e.g. "Q4_K_M/Qwen3.5-..." → "Qwen3.5-...")
      let nameOnly = URL(fileURLWithPath: shardBase).lastPathComponent
      return parseQuant(filename: nameOnly + ".gguf")
    }

    // Quantization is the last segment after the final "-"
    // e.g. "Llama-3.2-1B-Instruct-Q4_K_M" → "Q4_K_M"
    guard let lastDash = base.lastIndex(of: "-") else { return nil }
    let candidate = String(base[base.index(after: lastDash)...])

    // Validate it looks like a quantization label (starts with Q, F, IQ, etc.)
    let upper = candidate.uppercased()
    let quantPrefixes = ["Q", "F", "IQ", "BF"]
    if quantPrefixes.contains(where: { upper.hasPrefix($0) }) {
      return candidate
    }

    return nil
  }

  /// Returns true if the filename matches the split-shard pattern.
  /// e.g. "model-00001-of-00003.gguf" → true
  static func isSplitShard(_ filename: String) -> Bool {
    splitShardPattern.firstMatch(
      in: filename, range: NSRange(filename.startIndex..., in: filename)
    ) != nil
  }

  /// Returns true if this is the first shard of a split model.
  /// e.g. "model-00001-of-00003.gguf" → true
  /// e.g. "model-00002-of-00003.gguf" → false
  static func isFirstShard(_ filename: String) -> Bool {
    guard
      let match = splitShardPattern.firstMatch(
        in: filename, range: NSRange(filename.startIndex..., in: filename)
      )
    else { return false }

    if let shardRange = Range(match.range(at: 1), in: filename) {
      return filename[shardRange] == "00001"
    }
    return false
  }

  /// Returns the declared shard count of a split-shard filename.
  /// e.g. "model-00001-of-00003.gguf" → 3
  static func shardTotal(_ filename: String) -> Int? {
    guard
      let match = splitShardPattern.firstMatch(
        in: filename, range: NSRange(filename.startIndex..., in: filename)
      ),
      let totalRange = Range(match.range(at: 2), in: filename)
    else { return nil }
    return Int(filename[totalRange])
  }

  /// Returns the base name for a split shard (everything before the shard pattern).
  /// e.g. "model-00001-of-00003.gguf" → "model"
  static func splitShardBaseName(_ filename: String) -> String? {
    guard
      let match = splitShardPattern.firstMatch(
        in: filename, range: NSRange(filename.startIndex..., in: filename)
      )
    else { return nil }

    let matchRange = Range(match.range, in: filename)!
    let base = String(filename[..<matchRange.lowerBound])
    // Remove trailing dash if present
    if base.hasSuffix("-") {
      return String(base.dropLast())
    }
    return base
  }

  // MARK: - Private

  /// Regex matching split shard filenames: -NNNNN-of-NNNNN.gguf
  private static let splitShardPattern: NSRegularExpression = {
    try! NSRegularExpression(pattern: #"-(\d{5})-of-(\d{5})\.gguf$"#, options: .caseInsensitive)
  }()
}
