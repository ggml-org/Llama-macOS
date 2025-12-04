import Foundation

/// Centralized access to simple persisted preferences.
enum UserSettings {
  private enum Keys {
    static let preferQuantizedModels = "preferQuantizedModels"
    static let hasSeenWelcome = "hasSeenWelcome"
    static let exposeToNetwork = "exposeToNetwork"
  }

  private static let defaults = UserDefaults.standard

  /// Whether to prefer quantized models over full-precision ones when both are available.
  /// Defaults to `true` to save memory and disk space.
  static var preferQuantizedModels: Bool {
    get {
      // Default to true if not set
      if defaults.object(forKey: Keys.preferQuantizedModels) == nil {
        return true
      }
      return defaults.bool(forKey: Keys.preferQuantizedModels)
    }
    set {
      guard defaults.bool(forKey: Keys.preferQuantizedModels) != newValue else { return }
      defaults.set(newValue, forKey: Keys.preferQuantizedModels)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

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
}
