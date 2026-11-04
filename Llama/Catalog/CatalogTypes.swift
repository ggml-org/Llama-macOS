import Foundation

/// Wire values and presentation facts shared by catalog loading and Discover.
enum Catalog {
  // MARK: - Wire format
  //
  // Mirrors the catalog's published shape: family → size → build. Only the
  // fields the app reads are decoded; everything else (publisher prose, etc.)
  // is the website's concern and is ignored here.

  /// A downloadable quant of a size — the same weights at a given quantization.
  /// Each build carries its own repo since quants sometimes live in different
  /// orgs (e.g. Q4 under the publisher, Q8 mirrored under ggml-org).
  struct Build: Decodable {
    let quant: String?
    let size: String?  // human label, e.g. "5.0 GB"
    let repo: String  // "{org}/{repo}"
  }

  /// A parameter tier within a family, e.g. "Gemma 4 E4B". The catalog's
  /// `name` is not decoded: rows are titled by the repo's id base, so the
  /// curated display name is the website's concern only.
  struct Size: Decodable {
    let inputModalities: [String]
    /// Memory cap for featuring, like `Family.maxMemGb` but for one size: on
    /// Macs with more RAM than this, the size is not suggested (e.g. the small
    /// Gemma 4 E-series on 32 GB+ Macs). Absent → the family's cap alone applies.
    let maxMemGb: UInt64?
    /// Whether the catalog marks this size as the suggested starting point for
    /// newcomers. The row gets a "Good first model" badge and is listed first.
    /// Absent → false.
    let goodFirstModel: Bool?
    let builds: [Build]

    private enum CodingKeys: String, CodingKey {
      case inputModalities, vision, maxMemGb, goodFirstModel, builds
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      // Released v1 catalogs contain only vision. Normalize at the wire
      // boundary; an explicit input list, including [], is authoritative.
      inputModalities =
        try values.decodeIfPresent([String].self, forKey: .inputModalities)
        ?? (values.decodeIfPresent(Bool.self, forKey: .vision) == true
          ? ["text", "image"] : ["text"])
      maxMemGb = try values.decodeIfPresent(UInt64.self, forKey: .maxMemGb)
      goodFirstModel = try values.decodeIfPresent(Bool.self, forKey: .goodFirstModel)
      builds = try values.decode([Build].self, forKey: .builds)
    }
  }

  /// A named release line, e.g. "Gemma 4". Holds the shared metadata.
  struct Family: Decodable {
    let brand: String
    /// Whether the catalog flags this family for in-app highlighting. Absent → false.
    let featured: Bool?
    /// Memory cap for featuring: on Macs with more RAM than this, the family is
    /// not suggested even though it would fit. Lets the catalog mark a family as
    /// a low-memory pick (e.g. Gemma 3 on 8 GB Macs) without the app hardcoding
    /// curation. Absent → no cap.
    let maxMemGb: UInt64?
    let sizes: [Size]
  }

  // MARK: - Featured suggestions

  /// One catalog pick, resolved to a single build for this Mac. This is the unit
  /// the Discover section renders and installs from. The `repo`, run through
  /// `Model.idBase`, matches the pre-colon prefix of the model id the resolver
  /// produces, so the Discover section can hide a suggestion once its repo is
  /// installed.
  struct Suggestion {
    let brand: String  // "Gemma" — drives the logo
    let repo: String  // "{org}/{repo}" — the row title is its id base
    let quant: String?  // catalog quant label, e.g. "Q8_0"
    let sizeLabel: String?  // human size, e.g. "5.0 GB"
    let inputModalities: [String]
    let isGoodFirstModel: Bool  // catalog `goodFirstModel` flag — badged, listed first

    var hasVision: Bool { inputModalities.contains("image") }

    var subtitle: String {
      var parts: [String] = []
      if isGoodFirstModel { parts.append("Good first model") }
      if let sizeLabel, !sizeLabel.isEmpty { parts.append(sizeLabel) }
      if inputModalities.contains("audio") { parts.append("Audio input") }
      if inputModalities.contains("video") { parts.append("Video input") }
      return parts.joined(separator: "  ∣  ")
    }
  }

}
