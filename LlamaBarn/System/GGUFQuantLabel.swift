import Foundation

/// Swift port of `parseGGUFQuantLabel` from
/// [huggingface.js/packages/tasks/src/gguf.ts](https://github.com/huggingface/huggingface.js/blob/main/packages/tasks/src/gguf.ts).
///
/// We mirror HF's behavior byte-for-byte because the label round-trips between
/// their JavaScript (which emits `llamabarn://install?quant=…` on quant-sheet
/// click) and our Swift (which matches the param against each sibling's
/// parsed label in `HFRepoResolver`). Any divergence means a deeplink that
/// HF sends us would fail to match the very file HF intended.
enum GGUFQuantLabel {

  /// Canonical label alternatives, matching `GGMLFileQuantizationType`'s declaration
  /// order in huggingface.js. The order is load-bearing: regex alternation is
  /// leftmost-match-first, so — e.g. — `Q4_0` appearing before `Q4_0_4_4` means
  /// `Q4_0_4_4.gguf` parses to `Q4_0`, same quirk as HF's parser.
  static let quants: [String] = [
    "F32", "F16",
    "Q4_0", "Q4_1", "Q4_1_SOME_F16", "Q4_2", "Q4_3",
    "Q8_0", "Q5_0", "Q5_1",
    "Q2_K", "Q3_K_S", "Q3_K_M", "Q3_K_L",
    "Q4_K_S", "Q4_K_M", "Q5_K_S", "Q5_K_M", "Q6_K",
    "IQ2_XXS", "IQ2_XS", "Q2_K_S", "IQ3_XS", "IQ3_XXS", "IQ1_S",
    "IQ4_NL", "IQ3_S", "IQ3_M", "IQ2_S", "IQ2_M", "IQ4_XS", "IQ1_M",
    "BF16",
    "Q4_0_4_4", "Q4_0_4_8", "Q4_0_8_8",
    "TQ1_0", "TQ2_0",
    "MXFP4_MOE", "NVFP4", "Q1_0",
    "Q2_K_XL", "Q3_K_XL", "Q4_K_XL", "Q5_K_XL", "Q6_K_XL", "Q8_K_XL",
  ]

  /// `(UD-)?(F32|F16|…|Q8_K_XL)(_[A-Z]+)?`. Named groups exist in HF's JS regex
  /// (`<prefix>`, `<quant>`, `<sizeVariation>`) but we don't use them — we return
  /// the full match to stay compatible with HF's `match(...).at(-1)` behavior.
  private static let regex: NSRegularExpression = {
    let alternation = quants.joined(separator: "|")
    let pattern = "(UD-)?(\(alternation))(_[A-Z]+)?"
    return try! NSRegularExpression(pattern: pattern)
  }()

  /// Returns the last quant label match in `path` (HF's `.at(-1)` semantics) or
  /// nil if none present. The returned string is uppercased and includes any
  /// `UD-` prefix and trailing `_<SUFFIX>` — exactly what HF would put in the
  /// deeplink's `quant=` param.
  static func parse(_ path: String) -> String? {
    let upper = path.uppercased()
    let range = NSRange(upper.startIndex..., in: upper)
    let matches = regex.matches(in: upper, range: range)
    guard let last = matches.last,
      let r = Range(last.range, in: upper)
    else { return nil }
    return String(upper[r])
  }

  /// Convenience: true iff `a` and `b` parse to the same quant (case-insensitive).
  /// Used by `HFRepoResolver` to match URL-provided quants against siblings.
  static func matches(_ a: String, _ b: String) -> Bool {
    a.caseInsensitiveCompare(b) == .orderedSame
  }
}
