import Foundation

/// Shared selection policy for sidecar GGUFs (`mmproj*.gguf` vision projectors
/// and the speculative draft heads named by `draftHeadPrefixes`).
///
/// Two discovery paths need the exact same policy — the deeplink resolver
/// choosing among HF API siblings (`HFRepoResolver`) and the cache scan
/// choosing among on-disk files (`HFCache`) — and the resulting attachment is
/// identity-relevant (it feeds `models.ini`), so the policy lives here once
/// instead of being mirrored in both.
enum SidecarPicker {

  /// True for a vision-projector sidecar. The ggml-org convention is an
  /// `mmproj` prefix (`mmproj-*.gguf`), but community repos also use it as a
  /// suffix (e.g. `PaddleOCR-VL-1.6-GGUF-mmproj.gguf`), so match `mmproj`
  /// anywhere in the basename. Accepts full repo-relative paths; only the
  /// basename is considered.
  static func isMmproj(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent.lowercased()
    return name.contains("mmproj") && name.hasSuffix(".gguf")
  }

  /// Filename prefixes llama.cpp resolves as draft heads shipped beside a model
  /// (`find_best_sibling` callers in `common/download.cpp`): `mtp-`
  /// (multi-token prediction), `dflash-` (block-diffusion drafting), `eagle3-`,
  /// and `dspark-`. Each borrows the target's token embeddings and output
  /// projection, so none loads as a model on its own.
  ///
  /// We drive `mtp-` and `dflash-` (see `DraftHead`). The rest are listed so
  /// main-model selection skips them too: a head parses to the target's quant
  /// tag, so an unrecognised one collides on `{org}/{repo}:{TAG}` and the
  /// dedupe can keep the head and drop the real model. Keep in step with upstream -- a scheme we don't list is a
  /// scheme that shadows real models.
  static let draftHeadPrefixes = ["mtp-", "dflash-", "eagle3-", "dspark-"]

  /// True for any draft-head sidecar (see `draftHeadPrefixes`). Accepts full
  /// repo-relative paths; only the basename is considered.
  static func isDraftHead(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent.lowercased()
    guard name.hasSuffix(".gguf") else { return false }
    return draftHeadPrefixes.contains { name.hasPrefix($0) }
  }

  /// Picks the mmproj sidecar for `mainPath`. Repos routinely ship more than
  /// one (every current ggml-org VLM ships `mmproj-…-BF16` + `mmproj-…-Q8_0`),
  /// so ambiguity is the normal case, not a reason to skip: without an mmproj
  /// the model loads as text-only and image input silently disappears.
  static func mmproj(among names: [String], mainPath: String) -> String? {
    bestSibling(among: names, mainPath: mainPath, isCandidate: isMmproj)
  }

  /// Picks the draft-head sidecar for `mainPath`, of the most preferred kind
  /// the repo ships (`DraftHead.preferenceOrder` -- DFlash before MTP). Kinds
  /// are tried one at a time, so a quant-matched MTP head never beats a DFlash
  /// head of a farther quant: the kind matters more than the quant. Within a
  /// kind, `tag` is the main file's canonical quant tag, which lets an exact
  /// `-<TAG>.gguf` head win over a merely near-in-bits one.
  ///
  /// This is where the app parts ways with `llama serve -hf`: plain `-hf`
  /// attaches no head unless asked for one by `--spec-type`. The kind of the
  /// returned path is `DraftHead(sidecarPath:)`.
  static func draftHead(among names: [String], mainPath: String, tag: String?) -> String? {
    for kind in DraftHead.preferenceOrder {
      let picked = bestSibling(among: names, mainPath: mainPath, tag: tag) {
        DraftHead(sidecarPath: $0) == kind
      }
      if let picked { return picked }
    }
    return nil
  }

  /// Port of llama.cpp's `find_best_sibling` (`common/download.cpp`), the
  /// function behind its `find_best_mmproj` / `find_best_mtp`. Keeping the two
  /// in step matters because the same repo has to resolve the same way whether
  /// the user installs it through us or through `llama serve -hf`.
  ///
  /// A candidate qualifies only if its directory path is a prefix of the main
  /// file's — the same directory, or an ancestor of it. That covers both
  /// real-world layouts in one rule: per-quant subdir repos that ship
  /// `Q4_K_M/mmproj-….gguf` beside the quant, and subdir repos that keep a
  /// single shared sidecar at the snapshot root. A sidecar in an unrelated
  /// sibling directory (another quant's) is rejected outright.
  ///
  /// Qualifying candidates rank by: deepest directory (so the main file's own
  /// directory beats the root), then an exact `tag` match, then the smallest
  /// distance in quant bits from the main file (`GGUFQuant.quantBits`) — which
  /// is what lands a Q4_K_M or Q8_0 model on the Q8_0 mmproj and a BF16 model
  /// on the BF16 one.
  ///
  /// One deliberate divergence: candidates are ranked in sorted order, so an
  /// exact tie resolves the same way every scan. Upstream leaves ties to
  /// manifest order; here the choice is written into `models.ini`, and a path
  /// that flips between scans would rewrite it for no reason.
  static func bestSibling(
    among names: [String],
    mainPath: String,
    tag: String? = nil,
    isCandidate: (String) -> Bool
  ) -> String? {
    let mainDirs = dirComponents(of: mainPath)
    let mainBits =
      tag.map(GGUFQuant.quantBits(forTag:)) ?? GGUFQuant.quantBits(forPath: mainPath)
    let tagUpper = tag?.uppercased()

    var best: (path: String, depth: Int, exact: Bool, diff: Int)?

    for path in names.sorted() where isCandidate(path) {
      let dirs = dirComponents(of: path)
      guard dirs.count <= mainDirs.count, mainDirs.starts(with: dirs) else { continue }

      let depth = dirs.count
      let diff = abs(GGUFQuant.quantBits(forPath: path) - mainBits)
      let exact = tagUpper.map { path.uppercased().contains("-\($0).") } ?? false

      if let best {
        let better =
          depth > best.depth
          || (depth == best.depth && exact && !best.exact)
          || (depth == best.depth && exact == best.exact && diff < best.diff)
        guard better else { continue }
      }
      best = (path, depth, exact, diff)
    }

    return best?.path
  }

  /// The directory components of a repo-relative path (`Q4_K_M/a.gguf` →
  /// `["Q4_K_M"]`, `a.gguf` → `[]`).
  private static func dirComponents(of path: String) -> [Substring] {
    Array(path.split(separator: "/").dropLast())
  }
}
