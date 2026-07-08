import Foundation

/// Shared selection policy for sidecar GGUFs (`mmproj*.gguf` vision projectors
/// and `mtp-….gguf` speculative draft heads).
///
/// Two discovery paths need the exact same policy — the deeplink resolver
/// choosing among HF API siblings (`HFRepoResolver`) and the cache scan
/// choosing among on-disk files (`HFCache`) — and the resulting attachment is
/// identity-relevant (it feeds `models.ini`), so the policy lives here once
/// instead of being mirrored in both.
enum SidecarPicker {

  /// True for a vision-projector sidecar (`mmproj*.gguf`). Accepts full
  /// repo-relative paths; only the basename is considered.
  static func isMmproj(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent.lowercased()
    return name.hasPrefix("mmproj") && name.hasSuffix(".gguf")
  }

  /// True for an MTP draft-head sidecar (`mtp-….gguf`) — the convention
  /// llama.cpp keys on (`find_best_mtp`). Accepts full repo-relative paths.
  static func isMtp(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent.lowercased()
    return name.hasPrefix("mtp-") && name.hasSuffix(".gguf")
  }

  /// Picks the mmproj sidecar from a list of candidate names: attach only when
  /// there's exactly one, skip when ambiguous — an mmproj is quant-agnostic, so
  /// we've no reliable way to pick among several (e.g. F16 vs Q8 variants).
  static func mmproj(among names: [String]) -> String? {
    let candidates = names.filter(isMmproj)
    guard candidates.count == 1 else { return nil }
    return candidates[0]
  }

  /// Picks the MTP draft head from a list of candidate names. Repos commonly
  /// ship one head per quant, so prefer the head whose quant matches the main
  /// (mirroring llama.cpp's `find_best_mtp`), falling back to the smallest by
  /// `sizeOf` — heads are tiny and any quant works as a draft, so size is the
  /// safe tie-breaker. `mainQuant` must be the canonical tag; each candidate's
  /// parsed label is canonicalized before comparing (parse keeps HF-style
  /// prefixes like `UD-`).
  static func mtp(
    among names: [String], mainQuant: String, sizeOf: (String) -> Int64
  ) -> String? {
    let candidates = names.filter(isMtp)
    guard !candidates.isEmpty else { return nil }

    if let exact = candidates.first(where: { candidate in
      GGUFQuantLabel.parse(candidate).map {
        GGUFQuantLabel.matches(GGUFQuantLabel.canonicalTag($0), mainQuant)
      } ?? false
    }) {
      return exact
    }

    return candidates.min { sizeOf($0) < sizeOf($1) }
  }
}
