import Foundation

/// Builds requests to Hugging Face -- the single place that decides which
/// headers go out, so the API lookup, the metadata HEADs and the downloads
/// can't drift apart.
enum HFRequest {
  /// A request carrying the app's User-Agent, plus the user's token when `url`
  /// is on Hugging Face.
  static func make(_ url: URL, token: String?) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
    // Match the host exactly or as a subdomain -- a bare `hasSuffix` would also
    // accept `evilhuggingface.co`, and this check is the only thing keeping the
    // token off a third-party host.
    let host = url.host ?? ""
    if let token, host == "huggingface.co" || host.hasSuffix(".huggingface.co") {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }
}
