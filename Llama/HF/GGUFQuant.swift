import Foundation

/// Quant naming lives in two forms, and this type owns both plus the boundary
/// between them:
///
/// - *label* — HF-style, keeps prefixes like Unsloth's `UD-` (`UD-Q4_K_XL`);
///   what filenames contain and what deeplink `quant=` params carry.
/// - *tag* — llama.cpp-canonical (`Q4_K_XL`); what model ids are built from.
///
/// `parseLabel` is a Swift port of `parseGGUFQuantLabel` from
/// [huggingface.js/packages/tasks/src/gguf.ts](https://github.com/huggingface/huggingface.js/blob/main/packages/tasks/src/gguf.ts).
///
/// We mirror HF's behavior byte-for-byte because the label round-trips between
/// their JavaScript (which emits `llamabarn://install?quant=…` on quant-sheet
/// click) and our Swift (which matches the param against each sibling's
/// parsed label in `HFRepoResolver`). Any divergence means a deeplink that
/// HF sends us would fail to match the very file HF intended. The only
/// divergence is additive (bare `MXFP4`, see below) — a superset can't break
/// labels HF emits, it only accepts more.
enum GGUFQuant {

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
    // MXFP4 (bare) is our extension: HF's enum only has MXFP4_MOE, but
    // gpt-oss GGUFs are named `*-mxfp4.gguf` and HF's UI emits `quant=mxfp4`
    // for them. Listed after MXFP4_MOE to preserve leftmost-match order.
    "MXFP4_MOE", "MXFP4", "NVFP4", "Q1_0",
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
  static func parseLabel(_ path: String) -> String? {
    let upper = path.uppercased()
    let range = NSRange(upper.startIndex..., in: upper)
    let matches = regex.matches(in: upper, range: range)
    guard let last = matches.last,
      let r = Range(last.range, in: upper)
    else { return nil }
    return String(upper[r])
  }

  /// The one path → quant-tag derivation for building model ids. Every id
  /// construction site (the deeplink resolver and the post-install cache scan)
  /// must go through this: the two paths have to produce byte-identical ids or
  /// pending download rows never match their landed files and never get reaped.
  ///
  /// Chain: HF label grammar over the whole repo-relative path (catches subdir
  /// prefixes and `UD-` labels) → `HFRepoParser.parseQuant` over the bare
  /// filename (legacy labels outside HF's enum) → `requested` (an explicit
  /// deeplink `quant=` param, if any) → `"unknown"`. The winner is
  /// canonicalized to llama.cpp's tag shape. File-derived labels outrank
  /// `requested` because the cache scan sees only the file — a requested label
  /// that won here would produce an id the scan can't reproduce.
  static func tag(forPath path: String, requested: String? = nil) -> String {
    let filename = URL(fileURLWithPath: path).lastPathComponent
    let label =
      parseLabel(path)
      ?? HFRepoParser.parseQuant(filename: filename)
      ?? requested
    return label.map(canonicalTag) ?? "unknown"
  }

  /// Convenience: true iff `a` and `b` parse to the same quant (case-insensitive).
  /// Used by `HFRepoResolver` to match URL-provided quants against siblings.
  static func matches(_ a: String, _ b: String) -> Bool {
    a.caseInsensitiveCompare(b) == .orderedSame
  }

  /// Canonicalizes a quant tag the way llama.cpp does (`canonical_tag` in
  /// `common/preset.cpp`): keep only the last `-`/`.`-delimited token,
  /// uppercased — so `UD-Q4_K_XL` becomes `Q4_K_XL`.
  ///
  /// Model ids must go through this because llama-server applies the same
  /// normalization to `models.ini` section names when it loads them. If we
  /// built ids with the HF-style label (which keeps prefixes like Unsloth's
  /// `UD-`), the server would silently rename the model and every request
  /// using our id — the webui chat link, external API clients — would 404.
  /// `parseLabel` stays HF-faithful for matching deeplink `quant=` params;
  /// this is only for the identity we route on.
  static func canonicalTag(_ label: String) -> String {
    let upper = label.uppercased()
    if let sep = upper.lastIndex(where: { $0 == "-" || $0 == "." }) {
      let token = upper[upper.index(after: sep)...]
      // llama.cpp's regex requires a non-empty [A-Z0-9_]+ token after the
      // separator; anything else falls back to the whole tag uppercased.
      if !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
        return String(token)
      }
    }
    return upper
  }
}
