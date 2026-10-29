import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI
import os

/// A Hugging Face account the user signed in to with "Sign in with Hugging
/// Face" (OAuth), as an alternative to pasting an access token.
struct HFAccount: Codable, Equatable {
  /// Shown in Settings so the user can tell which account is signed in.
  var username: String
  var accessToken: String
  /// Renews `accessToken` when it expires. Nil if HF didn't issue one, in which
  /// case the token is used until it stops working and the user signs in again.
  var refreshToken: String?
  /// When `accessToken` expires; nil if HF didn't say.
  var expiresAt: Date?
}

/// "Sign in with Hugging Face": the OAuth flow that gets the app a token for
/// gated downloads without the user creating and pasting one, plus keeping
/// that token fresh.
///
/// The flow is the standard one for a native app: authorization code + PKCE
/// through `ASWebAuthenticationSession`, which opens HF's consent page in the
/// user's browser session (so most users are already logged in to HF and just
/// click "Authorize") and hands back the redirect to our URL scheme. The OAuth
/// app is public -- no client secret, since one shipped in the app wouldn't
/// stay secret; PKCE is what protects the code exchange instead.
///
/// Main-actor isolated so concurrent callers share one refresh (see
/// `refreshIfNeeded`) and the stored account has a single writer.
@MainActor
enum HFAuth {
  private static let logger = Logger(subsystem: Logging.subsystem, category: "HFAuth")

  /// The public OAuth app registered on huggingface.co. Its redirect URIs must
  /// list both builds' callbacks (`llama://oauth/callback` and
  /// `llama-dev://oauth/callback`) -- HF matches custom schemes exactly.
  /// Owned by the `ggml-org` org (moved there from a maintainer's account,
  /// keeping the client ID that shipped builds use).
  private static let clientID = "32a98453-7e8e-4b35-86d2-de29ae91d231"

  /// `gated-repos` is the only scope downloads need: it reads public gated
  /// repos the user has been granted access to. Deliberately not `read-repos`
  /// -- that adds the user's private repos and a broader consent prompt for a
  /// rare case the pasted token still covers. `openid profile` is for the
  /// username Settings shows.
  private static let scopes = "openid profile gated-repos"

  private static let authorizeURL = URL(string: "https://huggingface.co/oauth/authorize")!
  private static let tokenURL = URL(string: "https://huggingface.co/oauth/token")!
  private static let userInfoURL = URL(string: "https://huggingface.co/oauth/userinfo")!

  /// Under the build's own scheme (`llama` / `llama-dev`), so the dev and
  /// production builds can be signed in independently, like the rest of their
  /// settings.
  private static var redirectURI: String { "\(LlamaURL.primaryScheme)://oauth/callback" }

  /// Refresh this long before the token actually expires, so a request built
  /// just before expiry doesn't arrive with a dead token. Same margin
  /// `huggingface_hub` uses.
  private static let refreshMargin: TimeInterval = 5 * 60

  /// The in-flight refresh, shared by everyone who asks while it runs. HF may
  /// rotate the refresh token on use, so two parallel refreshes with the same
  /// one could have the second rejected -- which would sign the user out.
  private static var refreshTask: Task<Void, Never>?

  // MARK: - Token

  /// The token requests to Hugging Face carry: the signed-in account's, else a
  /// pasted one. Use `token()` where you can await, so it's refreshed first.
  static var currentToken: String? {
    UserSettings.hfAccount?.accessToken ?? UserSettings.hfToken
  }

  /// `currentToken`, refreshed first if it's about to expire.
  static func token() async -> String? {
    await refreshIfNeeded()
    return currentToken
  }

  // MARK: - Sign in / out

  enum SignInError: LocalizedError {
    /// The redirect came back without a code (e.g. the user clicked "Deny").
    case denied(String?)
    /// The redirect's `state` didn't match the one we sent.
    case stateMismatch
    /// The code exchange or the userinfo lookup failed.
    case requestFailed(String)

    var errorDescription: String? {
      switch self {
      case .denied(let detail):
        return detail.map { "Hugging Face didn’t authorize the app: \($0)" }
          ?? "Hugging Face didn’t authorize the app."
      case .stateMismatch:
        return "The sign-in response didn’t match the request. Try again."
      case .requestFailed(let detail):
        return "Couldn’t complete sign-in: \(detail)"
      }
    }
  }

  /// Runs the browser sign-in and stores the resulting account. Returns nil if
  /// the user cancelled -- that's not an error worth an alert.
  ///
  /// Takes the SwiftUI `WebAuthenticationSession` (from the environment) so
  /// the browser sheet is anchored to the window that asked for it.
  static func signIn(using session: WebAuthenticationSession) async throws -> HFAccount? {
    // PKCE: the code is only redeemable with the verifier, which never leaves
    // the app -- so an intercepted redirect is useless to anyone else.
    let verifier = randomURLSafeString()
    let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    // `state` ties the redirect to this request.
    let state = randomURLSafeString()

    var comps = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
    comps.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: scopes),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]

    let callback: URL
    do {
      callback = try await session.authenticate(
        using: comps.url!,
        callback: .customScheme(LlamaURL.primaryScheme),
        additionalHeaderFields: [:]
      )
    } catch ASWebAuthenticationSessionError.canceledLogin {
      return nil
    }

    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    guard value("state") == state else { throw SignInError.stateMismatch }
    guard let code = value("code") else {
      throw SignInError.denied(value("error_description") ?? value("error"))
    }

    let tokens = try await requestTokens([
      "grant_type": "authorization_code",
      "code": code,
      "redirect_uri": redirectURI,
      "client_id": clientID,
      "code_verifier": verifier,
    ])
    let username = try await fetchUsername(accessToken: tokens.accessToken)

    let account = HFAccount(
      username: username,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
    )
    UserSettings.hfAccount = account
    // One credential at a time: the account replaces a pasted token, so
    // Settings never shows two and the user never wonders which one is used.
    UserSettings.hfToken = nil
    logger.info("Signed in to Hugging Face as \(username, privacy: .public)")
    return account
  }

  /// Forgets the account locally. The grant stays listed under the user's
  /// connected apps on HF, where they can revoke it -- revoking from here would
  /// need an endpoint HF doesn't document.
  static func signOut() {
    UserSettings.hfAccount = nil
    logger.info("Signed out of Hugging Face")
  }

  // MARK: - Refresh

  /// Renews the account's access token if it expires within `refreshMargin`.
  /// No-op for a pasted token, a token without an expiry, or no account.
  static func refreshIfNeeded() async {
    guard let account = UserSettings.hfAccount,
      let expiresAt = account.expiresAt,
      let refreshToken = account.refreshToken,
      expiresAt.timeIntervalSinceNow < refreshMargin
    else { return }

    if let refreshTask {
      await refreshTask.value
      return
    }
    let task = Task { await refresh(account: account, refreshToken: refreshToken) }
    refreshTask = task
    await task.value
    refreshTask = nil
  }

  private static func refresh(account: HFAccount, refreshToken: String) async {
    do {
      let tokens = try await requestTokens([
        "grant_type": "refresh_token",
        "refresh_token": refreshToken,
        "client_id": clientID,
      ])
      // The user may have signed out (or in again) while this ran; don't
      // resurrect or overwrite that.
      guard UserSettings.hfAccount == account else { return }
      var updated = account
      updated.accessToken = tokens.accessToken
      // HF may or may not rotate the refresh token; keep the old one if not.
      updated.refreshToken = tokens.refreshToken ?? refreshToken
      updated.expiresAt = tokens.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
      UserSettings.hfAccount = updated
      logger.info("Refreshed Hugging Face token")
    } catch TokenRequestError.rejected(let detail) {
      // The grant is gone (revoked on HF, or the refresh token expired), so the
      // account can't authenticate anything any more. Sign out rather than
      // keep sending a dead token -- downloads then go out anonymously, and a
      // gated one fails with the "sign in" guidance.
      logger.error("Hugging Face refresh rejected, signing out: \(detail, privacy: .public)")
      if UserSettings.hfAccount == account { signOut() }
    } catch {
      // Offline or HF hiccup: keep the account and try again on the next
      // request. The request in hand goes out with the old token.
      logger.error("Hugging Face refresh failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Requests

  private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case expiresIn = "expires_in"
    }
  }

  private enum TokenRequestError: LocalizedError {
    /// HF answered with a 4xx -- the code or refresh token isn't valid.
    case rejected(String)
    /// Anything else: network failure, 5xx, unparseable response.
    case failed(String)

    var errorDescription: String? {
      switch self {
      case .rejected(let detail), .failed(let detail): return detail
      }
    }
  }

  /// POSTs a form to the token endpoint. The app is a public client, so the
  /// only client authentication is `client_id` in the form.
  private static func requestTokens(_ form: [String: String]) async throws -> TokenResponse {
    var request = HFRequest.make(tokenURL, token: nil)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(formEncode(form).utf8)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw TokenRequestError.failed(error.localizedDescription)
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
    guard (200..<300).contains(status) else {
      // OAuth errors come back as `{"error": "...", "error_description": "..."}`.
      let body = String(data: data, encoding: .utf8) ?? ""
      let detail = "HTTP \(status) \(body)"
      throw (400..<500).contains(status)
        ? TokenRequestError.rejected(detail) : TokenRequestError.failed(detail)
    }
    do {
      return try JSONDecoder().decode(TokenResponse.self, from: data)
    } catch {
      throw TokenRequestError.failed("unexpected token response")
    }
  }

  /// The account's username, from the OpenID userinfo endpoint.
  private static func fetchUsername(accessToken: String) async throws -> String {
    struct UserInfo: Decodable {
      let preferred_username: String?
      let name: String?
    }
    let request = HFRequest.make(userInfoURL, token: accessToken)
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? -1
      guard (200..<300).contains(status) else {
        throw SignInError.requestFailed("userinfo returned HTTP \(status)")
      }
      let info = try JSONDecoder().decode(UserInfo.self, from: data)
      guard let username = info.preferred_username ?? info.name else {
        throw SignInError.requestFailed("userinfo had no username")
      }
      return username
    } catch let error as SignInError {
      throw error
    } catch {
      throw SignInError.requestFailed(error.localizedDescription)
    }
  }

  // MARK: - Helpers

  /// `application/x-www-form-urlencoded` body. Encodes everything outside the
  /// RFC 3986 unreserved set -- `urlQueryAllowed` would leave `+`, `&` and `=`
  /// raw, which a form body reads as separators.
  private static func formEncode(_ form: [String: String]) -> String {
    let unreserved = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    return form.map { key, value in
      let k = key.addingPercentEncoding(withAllowedCharacters: unreserved) ?? key
      let v = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
      return "\(k)=\(v)"
    }.joined(separator: "&")
  }

  /// 32 random bytes, base64url-encoded (43 chars) -- the length RFC 7636
  /// recommends for a PKCE verifier; also used for `state`.
  private static func randomURLSafeString() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return base64URL(Data(bytes))
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
