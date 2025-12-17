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
    static let showEstimatedMemoryUsage = "showEstimatedMemoryUsage"
    static let defaultContextWindow = "defaultContextWindow"
    static let memoryUsageCap = "memoryUsageCap"
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

  /// Whether to show estimated memory usage next to size on disk.
  /// Shows memory usage for the default context length, and context length if different.
  /// Defaults to `false`.
  static var showEstimatedMemoryUsage: Bool {
    get {
      defaults.bool(forKey: Keys.showEstimatedMemoryUsage)
    }
    set {
      guard defaults.bool(forKey: Keys.showEstimatedMemoryUsage) != newValue else { return }
      defaults.set(newValue, forKey: Keys.showEstimatedMemoryUsage)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

  /// The maximum fraction of system memory that models are allowed to use.
  /// Defaults to 0.5 (4/8) for <128GB RAM, and 0.75 (6/8) for ≥128GB RAM.
  static var memoryUsageCap: Double {
    get {
      let val = defaults.double(forKey: Keys.memoryUsageCap)
      if val > 0 { return val }
      return SystemMemory.memoryMb >= 128 * 1024 ? 0.75 : 0.5
    }
    set {
      guard defaults.double(forKey: Keys.memoryUsageCap) != newValue else { return }
      defaults.set(newValue, forKey: Keys.memoryUsageCap)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

  /// Available memory cap options based on system RAM.
  static var availableMemoryUsageCaps: [Double] {
    if SystemMemory.memoryMb >= 128 * 1024 {
      return [0.25, 0.5, 0.75]  // 2/8, 4/8, 6/8
    } else {
      return [0.25, 0.375, 0.5]  // 2/8, 3/8, 4/8
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
