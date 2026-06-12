import Foundation

/// Maps a model family or brand name to a logo asset in
/// `Assets.xcassets/ModelLogos`. Without a curated catalog the brand is
/// inferred by keyword — the single table here serves both the installed rows
/// (matched on the parsed family name) and the Discover rows (matched on the
/// catalog's brand field), so the two can't drift apart.
enum ModelLogos {
  /// Keyword → logo asset. Several Mistral lines share one mark; GLM is z.ai's;
  /// Nemotron is NVIDIA's. Order only matters where keywords overlap (none do).
  private static let brands: [(keyword: String, asset: String)] = [
    ("qwen", "qwen"),
    ("gemma", "gemma"),
    ("openai", "gpt"),
    ("gpt", "gpt"),
    ("mistral", "mistral"),
    ("ministral", "mistral"),
    ("devstral", "mistral"),
    ("magistral", "mistral"),
    ("glm", "z"),
    ("nemotron", "nvidia"),
    ("nvidia", "nvidia"),
  ]

  /// Returns the asset name (e.g. "ModelLogos/qwen") for a family/brand name,
  /// or nil when no keyword matches — callers fall back to a generic symbol.
  static func asset(matching name: String) -> String? {
    let haystack = name.lowercased()
    guard let asset = brands.first(where: { haystack.contains($0.keyword) })?.asset
    else { return nil }
    return "ModelLogos/\(asset)"
  }
}
