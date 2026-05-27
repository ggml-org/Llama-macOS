import Foundation

/// Centralized access to simple persisted preferences.
enum UserSettings {
  enum SleepIdleTime: Int, CaseIterable {
    case disabled = -1
    #if DEBUG
      case thirtySec = 30
    #endif
    case fiveMin = 300
    case fifteenMin = 900
    case oneHour = 3600

    var displayName: String {
      switch self {
      case .disabled: return "Off"
      #if DEBUG
        case .thirtySec: return "30 sec (debug)"
      #endif
      case .fiveMin: return "5 min"
      case .fifteenMin: return "15 min"
      case .oneHour: return "1 hour"
      }
    }
  }

  private enum Keys {
    static let hasSeenWelcome = "hasSeenWelcome"
    static let exposeToNetwork = "exposeToNetwork"
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

  /// The network bind address for llama-server, or `nil` for localhost only.
  /// Accepts either a bool (`true` binds to `0.0.0.0`) or a specific IP address string.
  /// Examples:
  ///   `defaults write app.llamabarn.LlamaBarn exposeToNetwork -bool true` → binds to 0.0.0.0
  ///   `defaults write app.llamabarn.LlamaBarn exposeToNetwork -string "192.168.1.100"` → binds to that IP
  ///   `defaults delete app.llamabarn.LlamaBarn exposeToNetwork` → localhost only
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

  /// App's Application Support directory (~/Library/Application Support/LlamaBarn/).
  /// Holds models.ini and serves as llama-server's working directory.
  /// Auto-created on first access.
  static let appSupportDir: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LlamaBarn", isDirectory: true)
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
