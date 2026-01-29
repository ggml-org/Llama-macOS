import Foundation

/// Centralized access to simple persisted preferences.
enum UserSettings {
  enum SleepIdleTime: Int, CaseIterable {
    case disabled = -1
    case fiveMin = 300
    case fifteenMin = 900
    case oneHour = 3600

    var displayName: String {
      switch self {
      case .disabled: return "Off"
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
    static let modelStorageDirectory = "modelStorageDirectory"
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
    let obj = defaults.object(forKey: Keys.exposeToNetwork)
    // If it's a string, use it directly as the bind address
    if let str = obj as? String {
      return str
    }
    // If it's a bool and true, bind to all interfaces
    if let bool = obj as? Bool, bool {
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
  /// When nil, the model should use its highest compatible tier.
  static func selectedCtxTier(for modelId: String) -> ContextTier? {
    guard let dict = defaults.dictionary(forKey: Keys.selectedCtxTiers),
      let rawValue = dict[modelId] as? Int
    else { return nil }
    return ContextTier(rawValue: rawValue)
  }

  /// Sets the user-selected context tier for a model.
  /// Pass nil to clear the preference and use the default (highest compatible).
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

  // MARK: - Model Storage Directory

  /// The default directory for storing models (~/.llamabarn)
  static let defaultModelStorageDirectory: URL = {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      ".llamabarn", isDirectory: true)
  }()

  /// The directory where models are stored.
  /// Returns the user-configured path if set, otherwise the default (~/.llamabarn).
  /// Creates the directory if it doesn't exist.
  static var modelStorageDirectory: URL {
    get {
      let dir: URL
      if let path = defaults.string(forKey: Keys.modelStorageDirectory) {
        dir = URL(fileURLWithPath: path, isDirectory: true)
      } else {
        dir = defaultModelStorageDirectory
      }

      // Ensure directory exists
      if !FileManager.default.fileExists(atPath: dir.path) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      }

      return dir
    }
    set {
      // Store nil to reset to default, otherwise store the path
      if newValue == defaultModelStorageDirectory {
        defaults.removeObject(forKey: Keys.modelStorageDirectory)
      } else {
        defaults.set(newValue.path, forKey: Keys.modelStorageDirectory)
      }
    }
  }

  /// Whether a custom model storage directory is configured
  static var hasCustomModelStorageDirectory: Bool {
    defaults.string(forKey: Keys.modelStorageDirectory) != nil
  }

  /// Whether the configured model storage directory is accessible.
  /// Returns true if using default directory or if custom directory exists.
  static var isModelStorageDirectoryAvailable: Bool {
    let dir = modelStorageDirectory
    return FileManager.default.fileExists(atPath: dir.path)
  }
}
