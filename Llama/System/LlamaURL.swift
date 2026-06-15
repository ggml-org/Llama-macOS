import Foundation

/// Parsed representation of a `llama://` URL.
///
/// Only one verb today — `install` — but the URL shape (flat, verb-first) leaves
/// room for future actions (`load`, `open-settings`, ...) without restructuring.
enum LlamaURL: Equatable {
  /// `llama://install?repo={org}/{repo}[&quant={label}]`
  case install(repo: String, quant: String?)

  /// The URL schemes this build registers, read from `CFBundleURLTypes` in
  /// `Info.plist`. Production builds register `llama` and `llamabarn`; dev
  /// builds register `llama-dev` and `llamabarn-dev`, so a developer with both
  /// installed can route deeplinks deterministically (Launch Services would
  /// otherwise pick whichever build it ranked higher). The `llama` schemes are
  /// canonical post-rename to Llama; `llamabarn` is a deprecated alias kept only
  /// so old links keep working — don't advertise it in new links.
  private static let registeredSchemes: Set<String> = {
    guard
      let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
        as? [[String: Any]],
      let schemes = types.first?["CFBundleURLSchemes"] as? [String],
      !schemes.isEmpty
    else { return ["llama"] }
    return Set(schemes.map { $0.lowercased() })
  }()

  /// Parses a URL into a `LlamaURL`. Returns nil for anything that isn't a
  /// recognized verb under our registered scheme or that fails shallow
  /// validation (shape of `repo`). Deeper validation (quant label
  /// canonicalization, repo existence) happens downstream in `HFRepoResolver`
  /// / `GGUFQuantLabel`.
  static func parse(_ url: URL) -> LlamaURL? {
    guard let scheme = url.scheme?.lowercased(), registeredSchemes.contains(scheme)
    else { return nil }

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

  private static func parseInstall(query: [URLQueryItem]) -> LlamaURL? {
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
