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

  enum CacheType: String, CaseIterable {
    case f16 = "f16"
    case q8_0 = "q8_0"
    case q4_0 = "q4_0"

    var displayName: String {
      switch self {
      case .f16: return "F16"
      case .q8_0: return "Q8"
      case .q4_0: return "Q4"
      }
    }
  }

  private enum Keys {
    static let hasSeenWelcome = "hasSeenWelcome"
    static let exposeToNetwork = "exposeToNetwork"
    static let defaultContextWindow = "defaultContextWindow"
    static let cacheTypeK = "cacheTypeK"
    static let cacheTypeV = "cacheTypeV"
    static let flashAttention = "flashAttention"
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

  /// The cache type for K tensors.
  static var cacheTypeK: CacheType {
    get {
      let rawValue = defaults.string(forKey: Keys.cacheTypeK) ?? "q8_0"
      return CacheType(rawValue: rawValue) ?? .q8_0
    }
    set {
      guard defaults.string(forKey: Keys.cacheTypeK) != newValue.rawValue else { return }
      defaults.set(newValue.rawValue, forKey: Keys.cacheTypeK)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

  /// The cache type for V tensors.
  static var cacheTypeV: CacheType {
    get {
      let rawValue = defaults.string(forKey: Keys.cacheTypeV) ?? "q8_0"
      return CacheType(rawValue: rawValue) ?? .q8_0
    }
    set {
      guard defaults.string(forKey: Keys.cacheTypeV) != newValue.rawValue else { return }
      defaults.set(newValue.rawValue, forKey: Keys.cacheTypeV)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

  /// Whether flash attention is enabled.
  static var flashAttentionEnabled: Bool {
    get {
      if defaults.object(forKey: Keys.flashAttention) == nil { return true }
      return defaults.bool(forKey: Keys.flashAttention)
    }
    set {
      guard defaults.bool(forKey: Keys.flashAttention) != newValue else { return }
      defaults.set(newValue, forKey: Keys.flashAttention)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }
}
