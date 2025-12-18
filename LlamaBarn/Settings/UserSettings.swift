import Foundation

/// Centralized access to simple persisted preferences.
enum UserSettings {
  enum ContextWindowSize: Int, CaseIterable {
    case fourK = 4
    case sixteenK = 16
    case sixtyFourK = 64
    case max = -1

    var displayName: String {
      switch self {
      case .fourK: return "4k"
      case .sixteenK: return "16k"
      case .sixtyFourK: return "64k"
      case .max: return "Max"
      }
    }
  }

  private enum Keys {
    static let hasSeenWelcome = "hasSeenWelcome"
    static let exposeToNetwork = "exposeToNetwork"
    static let defaultContextWindow = "defaultContextWindow"
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

  /// Whether to expose llama-server to the network (bind to 0.0.0.0).
  /// Defaults to `false` (localhost only). When `true`, allows connections from other devices
  /// on the same network.
  static var exposeToNetwork: Bool {
    get {
      defaults.bool(forKey: Keys.exposeToNetwork)
    }
    set {
      guard defaults.bool(forKey: Keys.exposeToNetwork) != newValue else { return }
      defaults.set(newValue, forKey: Keys.exposeToNetwork)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

  /// The default context length in thousands of tokens.
  /// Defaults to 4k.
  static var defaultContextWindow: ContextWindowSize {
    get {
      let rawValue = defaults.integer(forKey: Keys.defaultContextWindow)
      return ContextWindowSize(rawValue: rawValue) ?? .fourK
    }
    set {
      guard defaults.integer(forKey: Keys.defaultContextWindow) != newValue.rawValue else { return }
      defaults.set(newValue.rawValue, forKey: Keys.defaultContextWindow)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }
}
