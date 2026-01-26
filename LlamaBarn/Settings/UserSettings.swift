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

  /// Available context tier options that users can enable/disable.
  /// Each case represents a context length in tokens.
  enum ContextTierOption: Int, CaseIterable {
    case k4 = 4096
    case k8 = 8192
    case k16 = 16384
    case k32 = 32768
    case k64 = 65536
    case k128 = 131072
    case k256 = 262144

    var label: String {
      switch self {
      case .k4: return "4k"
      case .k8: return "8k"
      case .k16: return "16k"
      case .k32: return "32k"
      case .k64: return "64k"
      case .k128: return "128k"
      case .k256: return "256k"
      }
    }

    /// Converts to the app's ContextTier enum if this option is enabled.
    var asContextTier: ContextTier? {
      ContextTier(rawValue: rawValue)
    }
  }

  /// Default enabled context tiers: 4k, 32k
  static let defaultContextTiers: Set<Int> = [
    ContextTierOption.k4.rawValue,
    ContextTierOption.k32.rawValue,
  ]

  private enum Keys {
    static let hasSeenWelcome = "hasSeenWelcome"
    static let exposeToNetwork = "exposeToNetwork"
    static let sleepIdleTime = "sleepIdleTime"
    static let enabledContextTiers = "enabledContextTiers"
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

  /// Returns the set of enabled context tier raw values (token counts).
  /// Defaults to 4k, 32k if not set.
  static var enabledContextTiers: Set<Int> {
    get {
      guard let arr = defaults.array(forKey: Keys.enabledContextTiers) as? [Int] else {
        return defaultContextTiers
      }
      return Set(arr)
    }
    set {
      let sorted = newValue.sorted()
      defaults.set(sorted, forKey: Keys.enabledContextTiers)
      NotificationCenter.default.post(name: .LBContextTiersDidChange, object: nil)
    }
  }

  /// Checks if a specific context tier option is enabled.
  static func isContextTierEnabled(_ option: ContextTierOption) -> Bool {
    enabledContextTiers.contains(option.rawValue)
  }

  /// Toggles a context tier option on or off.
  static func setContextTier(_ option: ContextTierOption, enabled: Bool) {
    var tiers = enabledContextTiers
    if enabled {
      tiers.insert(option.rawValue)
    } else {
      tiers.remove(option.rawValue)
    }
    enabledContextTiers = tiers
  }
}
