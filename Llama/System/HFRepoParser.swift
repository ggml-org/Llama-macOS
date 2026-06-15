import Foundation

/// Parsed metadata from a HuggingFace repo directory name.
/// Derived by splitting the repo name on `-` and classifying segments.
struct ParsedRepo {
  let org: String  // HF org, e.g. "bartowski"
  let repo: String  // Raw repo name, e.g. "Llama-3.2-1B-Instruct-GGUF"
  let name: String  // Model name, e.g. "Llama-3.2"
  let params: String?  // Parameter count, e.g. "1B", "270M"
  let tags: [String]  // Remaining segments, e.g. ["Instruct"]
}

/// Parses HuggingFace repo directory names and GGUF filenames into structured components.
/// Follows the same approach as the llama.cpp WebUI model selector.
enum HFRepoParser {

  /// Parses a repo dir name (e.g. "models--bartowski--Llama-3.2-1B-Instruct-GGUF")
  /// into structured components. Returns nil if the format is unrecognized.
  static func parse(repoDir: String) -> ParsedRepo? {
    // Extract org and repo from "models--{org}--{repo}"
    guard repoDir.hasPrefix("models--") else { return nil }

    // Split on "--" to get [models, org, repo]
    let dashDashParts = repoDir.components(separatedBy: "--")
    guard dashDashParts.count >= 3 else { return nil }

    let org = dashDashParts[1]
    let repo = dashDashParts[2...].joined(separator: "--")
    guard !org.isEmpty, !repo.isEmpty else { return nil }

    // Split repo name on "-" to classify segments.
    // Use a smarter split that preserves version numbers like "3.2":
    // We split on "-" but then rejoin segments that form version-like patterns.
    let segments = splitRepoName(repo)

    // Find the first params segment (e.g. "1B", "270M", "0.6B")
    let paramsIdx = segments.firstIndex(where: { isParams($0) })

    // Model name = segments before params (or all segments if no params found)
    let nameEndIdx = paramsIdx ?? segments.endIndex
    let nameSegments = Array(segments[..<nameEndIdx])

    // If name is empty (params is the first segment), use the full repo as name
    guard !nameSegments.isEmpty else {
      return ParsedRepo(org: org, repo: repo, name: repo, params: nil, tags: [])
    }

    let name = nameSegments.joined(separator: "-")

    // Params
    let params = paramsIdx.map { String(segments[$0]) }

    // Tags = segments after params, excluding GGUF/GGML
    let tagsStartIdx = paramsIdx.map { $0 + 1 } ?? segments.endIndex
    let excludedTags: Set<String> = ["GGUF", "GGML", "gguf", "ggml"]
    let tags = segments[tagsStartIdx...].filter { !excludedTags.contains($0) }

    return ParsedRepo(org: org, repo: repo, name: name, params: params, tags: tags)
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

  /// Regex matching parameter count segments like "1B", "0.6B", "270M"
  private static let paramsPattern: NSRegularExpression = {
    try! NSRegularExpression(pattern: #"^\d+(\.\d+)?[BbMmKkTt]$"#)
  }()

  /// Returns true if a segment looks like a parameter count (e.g. "1B", "270M", "0.6B")
  private static func isParams(_ segment: String) -> Bool {
    paramsPattern.firstMatch(
      in: segment, range: NSRange(segment.startIndex..., in: segment)
    ) != nil
  }

  /// Splits a repo name on "-", filtering empty segments.
  /// Version numbers like "3.2" stay intact since the dot isn't a split point.
  /// e.g. "Llama-3.2-1B-Instruct-GGUF" → ["Llama", "3.2", "1B", "Instruct", "GGUF"]
  private static func splitRepoName(_ repo: String) -> [String] {
    repo.components(separatedBy: "-").filter { !$0.isEmpty }
  }
}
