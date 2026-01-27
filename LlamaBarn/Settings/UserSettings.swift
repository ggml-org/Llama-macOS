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
}
