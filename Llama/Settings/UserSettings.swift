import Foundation

/// Centralized access to simple persisted preferences.
enum UserSettings {
  enum SleepIdleTime: Int, CaseIterable {
    // Case order = display order in the settings pill picker: intervals
    // ascending, with "Off" (never unload) last as the biggest "interval"
    #if DEBUG
      case thirtySec = 30
    #endif
    case fiveMin = 300
    case fifteenMin = 900
    case oneHour = 3600
    case disabled = -1

    var displayName: String {
      switch self {
      // Short labels keep the settings pill picker compact
      #if DEBUG
        case .thirtySec: return "30s"
      #endif
      case .fiveMin: return "5m"
      case .fifteenMin: return "15m"
      case .oneHour: return "1h"
      case .disabled: return "Off"
      }
    }
  }

  private enum Keys {
    static let hasSeenWelcome = "hasSeenWelcome"
    static let hasSetDefaultLaunchAtLogin = "hasSetDefaultLaunchAtLogin"
    static let exposeToNetwork = "exposeToNetwork"
    static let serverPort = "serverPort"
    static let customServerArgs = "customServerArgs"
    static let sleepIdleTime = "sleepIdleTime"
    static let selectedCtxTiers = "selectedCtxTiers"
    static let hfCacheDirectory = "hfCacheDirectory"
    static let hfToken = "hfToken"
  }

  private static let defaults = UserDefaults.standard

  /// Whether the user has seen the welcome popover on first launch.
  static var hasSeenWelcome: Bool {
    get {
      defaults.bool(forKey: Keys.hasSeenWelcome)
    }
    set {
      defaults.set(newValue, forKey: Keys.hasSeenWelcome)
    }
  }

  /// Whether we've applied the one-time launch-at-login default (enabled on
  /// first launch). Guards against re-enabling it on later launches after the
  /// user has deliberately turned it off in Settings.
  static var hasSetDefaultLaunchAtLogin: Bool {
    get {
      defaults.bool(forKey: Keys.hasSetDefaultLaunchAtLogin)
    }
    set {
      defaults.set(newValue, forKey: Keys.hasSetDefaultLaunchAtLogin)
    }
  }

  /// The network bind address for llama-server, or `nil` for localhost only.
  /// Accepts either a bool (`true` binds to `0.0.0.0`) or a specific IP address string.
  /// Examples:
  ///   `defaults write app.llama.Llama exposeToNetwork -bool true` → binds to 0.0.0.0
  ///   `defaults write app.llama.Llama exposeToNetwork -string "192.168.1.100"` → binds to that IP
  ///   `defaults delete app.llama.Llama exposeToNetwork` → localhost only
  static var networkBindAddress: String? {
    let raw = defaults.object(forKey: Keys.exposeToNetwork)
    // If it's a string, use it directly as the bind address
    if let str = raw as? String {
      return str
    }
    // If it's a bool and true, bind to all interfaces
    if let bool = raw as? Bool, bool {
      return "0.0.0.0"
    }
    // Not set or false → localhost only
    return nil
  }

  /// Valid range for a user-set server port. The lower bound is 1024 because
  /// ports below that are privileged and llama serve (running as the user)
  /// can't bind them -- restricting here avoids a confusing bind failure.
  static let serverPortRange = 1024...65535

  /// The user-set port the server listens on, or `nil` to use the default
  /// (`LlamaServer.defaultPort`). Out-of-range stored values read as `nil`.
  static var serverPort: Int? {
    get {
      let value = defaults.integer(forKey: Keys.serverPort)
      return serverPortRange.contains(value) ? value : nil
    }
    set {
      // Normalize: keep only an in-range value, otherwise fall back to default.
      let normalized = newValue.flatMap { serverPortRange.contains($0) ? $0 : nil }
      // Avoid a redundant change notification (which would needlessly restart
      // the server) when the effective value isn't actually changing.
      guard normalized != serverPort else { return }
      if let normalized {
        defaults.set(normalized, forKey: Keys.serverPort)
      } else {
        defaults.removeObject(forKey: Keys.serverPort)
      }
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

  /// Additional arguments appended to `llama serve`, or `nil` for none.
  /// Whitespace-only stored values read as unset.
  static var customServerArguments: String? {
    get {
      guard let value = defaults.string(forKey: Keys.customServerArgs) else { return nil }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    set {
      // Normalize: keep only a non-empty string, otherwise fall back to no extra flags.
      var normalized = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
      if normalized?.isEmpty == true { normalized = nil }
      // Avoid a redundant change notification (which would needlessly restart
      // the server) when the effective value isn't actually changing.
      guard normalized != customServerArguments else { return }
      if let normalized {
        defaults.set(normalized, forKey: Keys.customServerArgs)
      } else {
        defaults.removeObject(forKey: Keys.customServerArgs)
      }
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

  /// Whether additional server arguments are configured
  static var hasCustomServerArguments: Bool {
    customServerArguments != nil
  }

  /// Flags the app owns because health checks and UI URLs read
  /// `LlamaServer.port` / `resolvedHost`.
  private static let appOwnedServerArgumentFlags: Set<String> = ["--port", "--host"]

  /// Tokenizes the user-entered server arguments into argv elements. Quotes are
  /// stripped while keeping values with spaces together, so advanced flags can
  /// be passed through without exposing a full shell parser.
  static var customServerArgumentTokens: [String] {
    guard let arguments = customServerArguments else { return [] }
    return filterAppOwnedServerArguments(tokenizeServerArguments(arguments))
  }

  private static func tokenizeServerArguments(_ input: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var activeQuote: Character?
    var hasToken = false

    for char in input {
      if let quote = activeQuote {
        if char == quote {
          activeQuote = nil
        } else {
          current.append(char)
        }
        hasToken = true
        continue
      }

      if char == "\"" || char == "'" {
        activeQuote = char
        hasToken = true
      } else if char.isWhitespace {
        if hasToken {
          tokens.append(current)
          current.removeAll()
          hasToken = false
        }
      } else {
        current.append(char)
        hasToken = true
      }
    }

    if hasToken {
      tokens.append(current)
    }

    return tokens
  }

  private static func filterAppOwnedServerArguments(_ tokens: [String]) -> [String] {
    var filtered: [String] = []
    var index = tokens.startIndex

    while index < tokens.endIndex {
      let token = tokens[index]

      if appOwnedServerArgumentFlags.contains(token) {
        let next = tokens.index(after: index)
        if next < tokens.endIndex, !tokens[next].hasPrefix("-") {
          index = tokens.index(after: next)
        } else {
          index = next
        }
        continue
      }

      if let equalsIndex = token.firstIndex(of: "="),
        appOwnedServerArgumentFlags.contains(String(token[..<equalsIndex]))
      {
        index = tokens.index(after: index)
        continue
      }

      filtered.append(token)
      index = tokens.index(after: index)
    }

    return filtered
  }

  /// How long to wait before unloading the model from memory when idle.
  /// Defaults to 5 minutes.
  static var sleepIdleTime: SleepIdleTime {
    get {
      let value = defaults.integer(forKey: Keys.sleepIdleTime)
      // 0 is returned if key is missing, which is not a valid case, so fallback to .fiveMin
      return SleepIdleTime(rawValue: value) ?? .fiveMin
    }
    set {
      guard defaults.integer(forKey: Keys.sleepIdleTime) != newValue.rawValue else { return }
      defaults.set(newValue.rawValue, forKey: Keys.sleepIdleTime)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

  // MARK: - Context Tier Preferences

  /// Returns the user-selected context tier for a model, or nil if not set.
  /// When nil, the model should use the default 4K tier.
  static func selectedCtxTier(for modelId: String) -> ContextTier? {
    guard let dict = defaults.dictionary(forKey: Keys.selectedCtxTiers),
      let rawValue = dict[modelId] as? Int
    else { return nil }
    return ContextTier(rawValue: rawValue)
  }

  /// Sets the user-selected context tier for a model.
  /// Pass nil to clear the preference and use the default (4K).
  static func setSelectedCtxTier(_ tier: ContextTier?, for modelId: String) {
    var dict = defaults.dictionary(forKey: Keys.selectedCtxTiers) ?? [:]
    if let tier {
      dict[modelId] = tier.rawValue
    } else {
      dict.removeValue(forKey: modelId)
    }
    defaults.set(dict, forKey: Keys.selectedCtxTiers)
    NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
  }

  // MARK: - Application Support Directory

  /// App's Application Support directory (~/Library/Application Support/Llama/).
  /// Holds models.ini and serves as llama-server's working directory.
  /// Auto-created on first access. (The pre-rename `LlamaBarn/` dir is left
  /// orphaned; models.ini is regenerated from the cache scan, so nothing's lost.)
  static let appSupportDir: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Llama", isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
  }()

  // MARK: - HF Cache Directory

  /// The default HF cache directory (~/.cache/huggingface/hub)
  static let defaultHFCacheDirectory: URL = {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
  }()

  /// The HF cache directory where new model downloads are stored.
  /// Shared with llama.cpp and other HF-aware tools.
  /// Defaults to ~/.cache/huggingface/hub, can be overridden in Settings.
  static var hfCacheDirectory: URL {
    get {
      let dir: URL
      if let path = defaults.string(forKey: Keys.hfCacheDirectory) {
        dir = URL(fileURLWithPath: path, isDirectory: true)
      } else {
        dir = defaultHFCacheDirectory
      }

      // Ensure directory exists
      if !FileManager.default.fileExists(atPath: dir.path) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      }

      return dir
    }
    set {
      if newValue == defaultHFCacheDirectory {
        defaults.removeObject(forKey: Keys.hfCacheDirectory)
      } else {
        defaults.set(newValue.path, forKey: Keys.hfCacheDirectory)
      }
    }
  }

  /// Whether a custom HF cache directory is configured
  static var hasCustomHFCacheDirectory: Bool {
    defaults.string(forKey: Keys.hfCacheDirectory) != nil
  }

  // MARK: - Hugging Face Token

  /// Optional token that authenticates downloads from Hugging Face.
  /// Stored in UserDefaults (not Keychain) — fine given most users would use
  /// a fine-grained token with minimal permissions.
  static var hfToken: String? {
    get {
      defaults.string(forKey: Keys.hfToken)
    }
    set {
      if let newValue, !newValue.isEmpty, isValidHFToken(newValue) {
        defaults.set(newValue, forKey: Keys.hfToken)
      } else {
        defaults.removeObject(forKey: Keys.hfToken)
      }
    }
  }

  /// Validates that a string looks like a Hugging Face access token.
  static func isValidHFToken(_ token: String) -> Bool {
    return token.hasPrefix("hf_")
      && token.count > 3
      && token.dropFirst(3).allSatisfy { $0.isLetter || $0.isNumber }
  }
}
