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
/// Each featured family shows every size this Mac can run, one row per size,
/// each resolved to the highest-precision quant that fits. "Full precision" is
/// whatever the catalog lists as the size's top build — Q8 for 16-bit families,
/// Q4 for QAT ones like Gemma 3 — and lower quants are strictly fallbacks. So a
/// row's quant is never a choice we made: a below-top quant means the top one
/// wouldn't run on this machine, nothing more. Which sizes exist and which
/// families are featured is the website's curation; the app only filters by
/// what fits (plus an optional per-family memory cap, also declared by the
/// catalog).
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

  /// A parameter tier within a family, e.g. "Gemma 4 E4B". The catalog's
  /// `name` is not decoded: rows are titled by the repo's id base, so the
  /// curated display name is the website's concern only.
  struct Size: Decodable {
    /// Whether this size supports image input. Absent → false.
    let vision: Bool?
    let builds: [Build]
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
    let hasVision: Bool  // catalog `vision` flag — shows the glasses marker
  }

  /// Fetches the catalog and returns one suggestion per fitting size of each
  /// featured family (see `picks(for:)`), in catalog order. Returns an empty
  /// list on any failure — Discover simply doesn't appear, and the user can
  /// still install from the web catalog or via deeplink.
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
      // Honor the catalog's per-family memory cap: skip families marked as
      // low-memory picks on machines with more RAM than their cap.
      .filter { family in
        family.maxMemGb.map { systemMemoryMb <= $0 * 1024 } ?? true
      }
      .flatMap { picks(for: $0, budgetMb: budgetMb) }
  }

  // MARK: - Selection

  /// Picks the builds to suggest for a family: one per size that fits this
  /// Mac's memory budget, in catalog order.
  ///
  /// Each size resolves to its highest-precision fitting quant — the largest
  /// build within budget — so full precision (whatever the size's top listed
  /// build is) wins whenever it fits and lower quants are strictly fallbacks.
  /// Quant selection is thus mechanical, not curatorial: a below-top quant
  /// always means the top one wouldn't run here. Sizes with no fitting build
  /// are dropped rather than shown as uninstallable rows; a family where
  /// nothing fits contributes no rows. If the whole featured set is too big,
  /// the section is empty and the menu falls back to the "Browse models" link.
  private static func picks(for family: Family, budgetMb: Double) -> [Suggestion] {
    family.sizes.compactMap { size in
      // A build fits when its estimated weight memory is within budget. Unknown
      // sizes parse to 0 bytes and are treated as fitting (don't hide),
      // matching the resolver's posture.
      let fitting = size.builds.filter {
        Model.estimatedWeightFits(bytes: parseBytes($0.size), budgetMb: budgetMb)
      }
      // Best quant = biggest fitting download of this size.
      guard let best = fitting.max(by: { parseBytes($0.size) < parseBytes($1.size) }) else {
        return nil
      }
      return Suggestion(
        brand: family.brand,
        repo: best.repo, quant: best.quant, sizeLabel: best.size,
        hasVision: size.vision == true)
    }
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
