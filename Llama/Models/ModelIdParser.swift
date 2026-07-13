import Foundation

/// Presentation-only parse of a model id into a short name plus metadata
/// chips, mirroring the llama.cpp WebUI's default model rendering
/// (`tools/ui` `parseModelId`) so a model looks the same in our menu and in
/// the WebUI's picker. The id itself is never touched — every field here is
/// derived from the id string, so display can never disagree with what
/// `curl /v1/models` returns.
///
/// Simplified relative to upstream: our ids are always the clean
/// `{org}/{repo}:{TAG}` shape `Model.makeId` builds, so the file-path,
/// dot-quant, and trailing-dash-quant branches upstream carries are omitted.
/// When bumping the pinned llama.cpp version, glance at upstream's
/// `model-id.ts` constants for new quant/param conventions.
enum ModelIdParser {

  /// The parsed components of a model id, ready for rendering.
  struct Parsed {
    /// The id's pre-slash org, verbatim (e.g. "unsloth"). Nil for ids with
    /// no slash. Callers render `displayOrg`, not this.
    let org: String?
    /// Repo-name segments before the params segment, rejoined with dashes
    /// (e.g. "gemma-3", "Devstral-Small-2"). Falls back to the whole repo
    /// name (minus GGUF/GGML segments) when no params segment is found.
    let name: String
    /// Parameter-count chip, uppercased (e.g. "24B", "270M"); for MoE repos
    /// that name their activated params it's the combined form ("35B-A3B").
    let params: String?
    /// The id's post-colon quant tag, verbatim (e.g. "Q4_K_M"). Nil when the
    /// id has no colon (catalog rows before a quant is known) or the tag is
    /// the "unknown" fallback (unlabeled files).
    let quant: String?
    /// Leftover repo segments after the params segment (e.g. "it", "qat",
    /// "instruct", "2512"). Empty when no params segment is found — the
    /// leftovers stay in the name then, matching the WebUI.
    let tags: [String]

    /// The org as a row renders it: nil for the default org (`ggml-org`),
    /// the org verbatim for everything else. Hiding the default org keeps
    /// the common case (catalog installs) reading as a bare friendly name,
    /// while models pulled from other orgs keep the `org/` prefix they were
    /// installed by. A pure function of the id — never of what else is
    /// installed — so a row's rendering can't change when the library does.
    var displayOrg: String? {
      org == ModelIdParser.defaultOrg ? nil : org
    }
  }

  /// The org whose prefix is hidden in display: the app's canonical source —
  /// the catalog and recommendations draw from it, so its models are the
  /// unmarked common case. Every other org renders as part of the name.
  static let defaultOrg = "ggml-org"

  /// Container-format segments dropped from display — every model is a GGUF,
  /// so the suffix carries no information on screen. (The id keeps it.)
  private static let ignoredSegments: Set<String> = ["GGUF", "GGML"]

  /// Parameter-count segment, e.g. "7B", "1.5b", "270M". The optional
  /// leading `E` covers Gemma's effective-params sizes ("E2B", "E4B") —
  /// upstream's parser misses these (its regex requires a leading digit),
  /// so this is a deliberate divergence in the direction of correctness.
  private static let paramsRe = /^[Ee]?\d+(\.\d+)?[BbMmKkTt]$/

  /// Activated-parameter-count segment for MoE repos, e.g. "A3B", "a2.4b".
  private static let activatedParamsRe = /^[Aa]\d+(\.\d+)?[BbMmKkTt]$/

  /// What a row visibly renders when tags are hidden: org prefix + name +
  /// params + quant. Two ids with equal keys would look identical in a list,
  /// so callers use key collisions to decide when a row needs its tags shown
  /// after all. The displayed org (not the raw one) is what's included, so
  /// two same-named repos from different orgs don't count as colliding — the
  /// `org/` prefix already tells them apart.
  static func displayKey(_ id: String) -> String {
    let parsed = parse(id)
    return [parsed.displayOrg ?? "", parsed.name, parsed.params ?? "", parsed.quant ?? ""]
      .joined(separator: "|")
  }

  static func parse(_ id: String) -> Parsed {
    // Split off the post-colon quant tag and the pre-slash org. Both always
    // exist in ids we build; catalog repos arrive without the colon.
    var rest = id
    var org: String?
    var quant: String?
    if let colonIdx = rest.lastIndex(of: ":") {
      let tag = String(rest[rest.index(after: colonIdx)...])
      // "unknown" is GGUFQuant's fallback for unlabeled files (the id needs
      // *some* tag), not information — rendering it as a chip reads like an
      // error, so display treats it as no quant.
      if tag.caseInsensitiveCompare("unknown") != .orderedSame {
        quant = tag
      }
      rest = String(rest[..<colonIdx])
    }
    if let slashIdx = rest.firstIndex(of: "/") {
      org = String(rest[..<slashIdx])
      rest = String(rest[rest.index(after: slashIdx)...])
    }

    // Segment the repo name and drop container-format noise up front, so
    // "-GGUF" never reaches the name even when no params segment is found.
    let segments = rest.split(separator: "-").map(String.init)
      .filter { !ignoredSegments.contains($0.uppercased()) }

    // First params-looking segment is the name/metadata pivot; a later
    // activated-params segment (MoE) joins it as one combined chip.
    var paramsIdx: Int?
    var activatedIdx: Int?
    var params: String?
    for (idx, seg) in segments.enumerated() {
      if paramsIdx == nil, seg.wholeMatch(of: paramsRe) != nil {
        paramsIdx = idx
        params = seg.uppercased()
      } else if paramsIdx != nil, activatedIdx == nil,
        seg.wholeMatch(of: activatedParamsRe) != nil
      {
        activatedIdx = idx
        params = "\(params!)-\(seg.uppercased())"
      }
    }

    // Name = segments before params; tags = segments after, minus the
    // activated-params one. Without a params pivot the whole repo name is
    // the name and nothing becomes a tag.
    let pivot = paramsIdx ?? segments.count
    let name = segments[..<pivot].joined(separator: "-")
    var tags: [String] = []
    if let paramsIdx {
      for idx in (paramsIdx + 1)..<segments.count where idx != activatedIdx {
        tags.append(segments[idx])
      }
    }

    return Parsed(org: org, name: name, params: params, quant: quant, tags: tags)
  }
}
