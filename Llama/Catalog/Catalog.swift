import Foundation
import os.log

/// The remote model catalog.
///
/// Llama no longer ships a hard-coded catalog; curation lives on the web at
/// `llama.app`, which also publishes a JSON endpoint the app can
/// consume. We use it for a lightweight in-app "Discover" section — a handful of
/// featured families, up to two device-appropriate picks each — so a fresh
/// install can get a model running in a couple of clicks without first visiting
/// the website.
///
/// The two picks per family are a smaller, faster-to-download size and the
/// largest size that fits this machine's memory — so a user can try something
/// quickly or go straight for the most capable build their Mac can run. They're
/// shown unlabeled (the model name's param-size and the download size carry the
/// meaning), and collapse to a single row when they resolve to the same build
/// (small Macs, single-size families).
///
/// The full browsing experience stays on the web; the app only ever reads the
/// `featured` slice.
enum Catalog {
  private static let logger = Logger(subsystem: Logging.subsystem, category: "Catalog")

  /// Published catalog endpoint. Same URL for dev and production builds — the
  /// catalog is environment-agnostic; only the install deeplink scheme differs.
  static let endpoint = URL(string: "https://llama.app/v1/catalog.json")!

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

  /// A parameter tier within a family, e.g. "Gemma 4 E4B".
  struct Size: Decodable {
    let name: String
    /// Parameter count label, e.g. "4B", "270M". Drives the smaller-pick floor.
    /// Absent → treated as below any floor (never chosen as the smaller pick).
    let params: String?
    let builds: [Build]
  }

  /// A named release line, e.g. "Gemma 4". Holds the shared metadata.
  struct Family: Decodable {
    let name: String
    let brand: String
    /// Whether the catalog flags this family for in-app highlighting. Absent → false.
    let featured: Bool?
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
    let sizeName: String  // "Gemma 4 E4B" — the row title
    let repo: String  // "{org}/{repo}"
    let quant: String?  // catalog quant label, e.g. "Q8_0"
    let sizeLabel: String?  // human size, e.g. "5.0 GB"
  }

  /// Fetches the catalog and returns up to two suggestions per featured family
  /// (a smaller size and the largest that fits — see `picks(for:)`), in catalog
  /// order. Returns an empty list on any failure — Discover simply doesn't appear,
  /// and the user can still install from the web catalog or via deeplink.
  static func fetchFeatured(systemMemoryMb: UInt64) async -> [Suggestion] {
    let families: [Family]
    do {
      let (data, response) = try await URLSession.shared.data(from: endpoint)
      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        logger.error("Catalog fetch returned non-2xx")
        return []
      }
      families = try JSONDecoder().decode([Family].self, from: data)
    } catch {
      logger.error("Catalog fetch failed: \(error.localizedDescription)")
      return []
    }

    let budgetMb = Model.memoryBudget(systemMemoryMb: systemMemoryMb)
    return
      families
      .filter { $0.featured == true }
      .flatMap { picks(for: $0, budgetMb: budgetMb) }
  }

  // MARK: - Selection

  /// Minimum parameter count (in millions) for the smaller pick. That row is
  /// meant to be the fastest way to a *useful* running model, so we skip the
  /// sub-billion "toy" sizes that would make a poor first impression. 3B sits in
  /// the gap common families leave between their small tier (~1–2B) and their
  /// first genuinely capable size (~4B), so the floor reliably lands on that
  /// 4B-class build rather than a 270M/1B one.
  private static let smallerPickMinParamsMillions = 3_000.0

  /// A flattened (size, build) candidate, tagged with parsed numeric size/params.
  private struct Candidate {
    let size: Size
    let build: Build
    let bytes: Int64
    let paramsMillions: Double
  }

  /// Picks up to two builds to suggest for a family, both bounded by this Mac's
  /// memory budget:
  ///
  /// - a smaller, faster-to-download size — the smallest fitting build at or
  ///   above the param floor, so it's quick to try yet not a toy.
  /// - the largest fitting build — the most capable size this Mac can run.
  ///
  /// Returns the two as `[smaller, largest]` when they differ. When they resolve
  /// to the same build, or no build clears the param floor, returns a single
  /// suggestion. Returns an empty array when nothing fits — Discover is a quick
  /// start surface, so a family this Mac can't run is dropped rather than shown
  /// as an uninstallable row. If the whole featured set is too big, the section
  /// is empty and the menu falls back to the "Browse models" link.
  private static func picks(for family: Family, budgetMb: Double) -> [Suggestion] {
    // Flatten to candidates, tagging each with its parsed byte size and params.
    let candidates: [Candidate] =
      family.sizes.flatMap { size in
        size.builds.map { build in
          Candidate(
            size: size, build: build,
            bytes: parseBytes(build.size),
            paramsMillions: parseParamsMillions(size.params))
        }
      }

    // A build fits when its estimated weight memory is within budget. Unknown
    // sizes are treated as fitting (don't hide), matching the resolver's posture.
    let fitting = candidates.filter {
      Model.estimatedWeightFits(bytes: $0.bytes, budgetMb: budgetMb)
    }
    guard let best = fitting.max(by: { $0.bytes < $1.bytes }) else { return [] }

    // Smaller pick: smallest fitting build that clears the param floor.
    let smaller =
      fitting
      .filter { $0.paramsMillions >= smallerPickMinParamsMillions }
      .min(by: { $0.bytes < $1.bytes })

    func suggestion(_ c: Candidate) -> Suggestion {
      Suggestion(
        brand: family.brand, sizeName: c.size.name,
        repo: c.build.repo, quant: c.build.quant, sizeLabel: c.build.size)
    }

    // When there's no distinct smaller build (none clears the floor, or it's the
    // same build as the largest), show a single row.
    guard let smaller = smaller, !sameBuild(smaller, best) else {
      return [suggestion(best)]
    }
    return [suggestion(smaller), suggestion(best)]
  }

  /// Whether two candidates point at the same downloadable build. Repo is unique
  /// per size and quant distinguishes builds within a repo, so the pair
  /// identifies a build.
  private static func sameBuild(_ a: Candidate, _ b: Candidate) -> Bool {
    a.build.repo == b.build.repo && a.build.quant == b.build.quant
  }

  /// Parses catalog size strings like "5.0 GB", "806 MB", "12.1 GB" into bytes.
  /// Uses decimal units (1 GB = 1e9) to match how the catalog and download UI
  /// report sizes. Returns 0 when missing or unparseable.
  private static func parseBytes(_ label: String?) -> Int64 {
    guard let label = label?.trimmingCharacters(in: .whitespaces), !label.isEmpty else { return 0 }
    let parts = label.split(separator: " ")
    guard let value = Double(parts.first ?? "") else { return 0 }
    let unit = parts.count > 1 ? parts[1].uppercased() : "GB"
    let multiplier: Double
    switch unit {
    case "GB", "G": multiplier = 1_000_000_000
    case "MB", "M": multiplier = 1_000_000
    case "KB", "K": multiplier = 1_000
    default: multiplier = 1_000_000_000
    }
    return Int64(value * multiplier)
  }

  /// Parses catalog param labels into millions of parameters. The catalog uses
  /// several shapes, so we read the *leading* number and the first B/M unit that
  /// follows it, ignoring anything else:
  ///
  /// - "4B" → 4000, "270M" → 270, "0.8B" → 800
  /// - "E4B" → 4000 (Gemma 3n's "effective params" notation; leading E ignored)
  /// - "122B-A10B" → 122000 (MoE total-active; we floor on the leading total)
  /// - "14B Reasoning" → 14000 (trailing words ignored)
  /// - "Flash" / missing → 0 (no leading number)
  ///
  /// A 0 result keeps it below any floor, so it's never the smaller pick (but it
  /// can still be the largest-fitting pick, where params don't matter).
  private static func parseParamsMillions(_ label: String?) -> Double {
    guard let label = label?.trimmingCharacters(in: .whitespaces), !label.isEmpty else { return 0 }
    var chars = Substring(label.uppercased())

    // Gemma 3n writes effective params as "E2B"/"E4B" — drop the leading marker.
    if chars.first == "E" { chars = chars.dropFirst() }

    // Read the leading number (digits and a decimal point).
    let numberStr = chars.prefix { $0.isNumber || $0 == "." }
    guard let value = Double(numberStr), value > 0 else { return 0 }

    // The unit is the first B/M after the number ("M" → millions, else billions).
    let rest = chars.dropFirst(numberStr.count)
    let multiplier = rest.first(where: { $0 == "B" || $0 == "M" }) == "M" ? 1.0 : 1_000.0
    return value * multiplier
  }
}

extension Catalog.Suggestion {
  /// Brand logo asset in `Assets.xcassets/ModelLogos`, matched from the catalog
  /// `brand`. Nil when the brand has no known mark — the row falls back to a
  /// generic system symbol. Keyed on brand (not family) since the catalog gives
  /// us the brand directly, e.g. "OpenAI" → the GPT mark.
  var brandLogoAsset: String? {
    ModelLogos.asset(matching: brand)
  }
}
