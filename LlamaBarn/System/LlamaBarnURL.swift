import Foundation

/// Parsed representation of a `llama://` URL.
///
/// Only one verb today — `install` — but the URL shape (flat, verb-first) leaves
/// room for future actions (`load`, `open-settings`, ...) without restructuring.
enum LlamaBarnURL: Equatable {
  /// `llama://install?repo={org}/{repo}[&quant={label}]`
  case install(repo: String, quant: String?)

  /// The URL scheme this build registers, read from `CFBundleURLTypes` in
  /// `Info.plist`. Production builds register `llama`; dev builds register
  /// `llama-dev`, so a developer with both installed can route deeplinks
  /// deterministically (Launch Services would otherwise pick whichever build
  /// it ranked higher).
  private static let registeredScheme: String = {
    guard
      let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
        as? [[String: Any]],
      let schemes = types.first?["CFBundleURLSchemes"] as? [String],
      let first = schemes.first
    else { return "llama" }
    return first.lowercased()
  }()

  /// Parses a URL into a `LlamaBarnURL`. Returns nil for anything that isn't a
  /// recognized verb under our registered scheme or that fails shallow
  /// validation (shape of `repo`). Deeper validation (quant label
  /// canonicalization, repo existence) happens downstream in `HFRepoResolver`
  /// / `GGUFQuantLabel`.
  static func parse(_ url: URL) -> LlamaBarnURL? {
    guard url.scheme?.lowercased() == registeredScheme else { return nil }

    // Use URLComponents to get a tolerant parse of the query string.
    // `host` normalizes to lowercase, so case in the authority doesn't matter.
    guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let host = comps.host?.lowercased()
    else { return nil }

    switch host {
    case "install":
      return parseInstall(query: comps.queryItems ?? [])
    default:
      return nil
    }
  }

  private static func parseInstall(query: [URLQueryItem]) -> LlamaBarnURL? {
    var repo: String?
    var quant: String?
    for item in query {
      switch item.name {
      case "repo": repo = item.value
      case "quant": quant = item.value
      default: continue  // Unknown params are forgiven — forward-compat.
      }
    }
    guard let repo, isValidRepo(repo) else { return nil }

    // Collapse empty quant ("&quant=") to nil. A malformed-but-present quant
    // is left to the resolver, which hard-rejects unparseable labels — we
    // don't fall through to default-quant resolution for a tampered value.
    let normalizedQuant = (quant?.isEmpty == true) ? nil : quant
    return .install(repo: repo, quant: normalizedQuant)
  }

  /// `repo` must be exactly `{org}/{name}` — one slash, no whitespace, non-empty
  /// halves. HF enforces much stricter rules on repo names server-side; we don't
  /// duplicate them here (a bogus repo just 404s on `/api/models/{repo}`).
  private static func isValidRepo(_ s: String) -> Bool {
    let parts = s.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return false }
    for part in parts {
      guard !part.isEmpty else { return false }
      if part.contains(where: { $0.isWhitespace }) { return false }
    }
    return true
  }
}
