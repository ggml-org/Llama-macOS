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
    static let sleepIdleTime = "sleepIdleTime"
    static let selectedCtxTiers = "selectedCtxTiers"
    static let extraServerArgs = "extraServerArgs"
    static let agentMode = "agentMode"
    static let hfCacheDirectory = "hfCacheDirectory"
    static let hfToken = "hfToken"
    static let modelLastUsedDates = "modelLastUsedDates"
    static let globalInputEnabled = "globalInputEnabled"
    static let globalInputShortcut = "globalInputShortcut"
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

  /// Per-model last-use timestamps (seconds since the reference date), keyed by
  /// model id. The single source of truth for recency: the sticky default is
  /// the newest entry, and the capture selector sorts by these values. Grows by
  /// one entry per model ever run; stale entries for deleted models are inert
  /// (callers re-validate ids against the installed set).
  private static var modelLastUsedDates: [String: Double] {
    get {
      defaults.dictionary(forKey: Keys.modelLastUsedDates) as? [String: Double] ?? [:]
    }
    set {
      defaults.set(newValue, forKey: Keys.modelLastUsedDates)
    }
  }

  /// The `id` of the last model the user deliberately ran (the newest entry in
  /// `modelLastUsedDates`), so the global-input capture panel has a sticky
  /// target even when nothing is loaded (e.g. right after launch). `nil` until
  /// the first model is run. Setting it stamps that model's use as "now";
  /// setting `nil` is a no-op.
  static var lastUsedModelId: String? {
    get {
      modelLastUsedDates.max { $0.value < $1.value }?.key
    }
    set {
      guard let id = newValue else { return }
      modelLastUsedDates[id] = Date().timeIntervalSinceReferenceDate
    }
  }

  /// When the given model was last deliberately run, as seconds since the
  /// reference date; `0` for a model that's never been run. Used to sort the
  /// capture selector by recency.
  static func modelLastUsed(for id: String) -> Double {
    modelLastUsedDates[id] ?? 0
  }

  /// Whether the global-input capture panel (default ⌥Space) is enabled. Off unless
  /// explicitly set, so the feature ships dormant for team testing before it's
  /// advertised:
  ///   `defaults write app.llama.Llama globalInputEnabled -bool true`
  /// Read once at launch (registering the hotkey), so a change needs a relaunch.
  static var globalInputEnabled: Bool {
    defaults.bool(forKey: Keys.globalInputEnabled)
  }

  /// The key combo that opens the global-input capture panel. Defaults to
  /// ⌥Space; stored (only when customized) as a `[keyCode, modifiers]` dict of
  /// the same Carbon values `GlobalHotkey.Combo` carries. The setter posts
  /// `LBGlobalInputShortcutDidChange` so the controller re-registers the
  /// hotkey immediately -- no relaunch needed (unlike `globalInputEnabled`).
  static var globalInputShortcut: GlobalHotkey.Combo {
    get {
      guard let dict = defaults.dictionary(forKey: Keys.globalInputShortcut),
        let keyCode = dict["keyCode"] as? Int,
        let modifiers = dict["modifiers"] as? Int
      else { return .optionSpace }
      return GlobalHotkey.Combo(keyCode: keyCode, modifiers: modifiers)
    }
    set {
      guard newValue != globalInputShortcut else { return }
      if newValue == .optionSpace {
        defaults.removeObject(forKey: Keys.globalInputShortcut)
      } else {
        defaults.set(
          ["keyCode": newValue.keyCode, "modifiers": newValue.modifiers],
          forKey: Keys.globalInputShortcut)
      }
      NotificationCenter.default.post(name: .LBGlobalInputShortcutDidChange, object: nil)
    }
  }

  /// Whether a non-default global-input shortcut is stored (drives the
  /// settings row's restore-default affordance).
  static var hasCustomGlobalInputShortcut: Bool {
    defaults.dictionary(forKey: Keys.globalInputShortcut) != nil
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

  // MARK: - Agent Mode

  /// Whether to pass `--agent` to `llama serve`, enabling the server's
  /// built-in tools (shell, filesystem, ...) and the UI's CORS/MCP proxy.
  /// This gives models running on the server the ability to act on the local
  /// machine, so it's strictly opt-in and off by default. The upstream flag's
  /// own help text warns against enabling it in untrusted environments --
  /// which notably includes serving on the network (`networkBindAddress`);
  /// the settings UI surfaces that caveat.
  static var agentMode: Bool {
    get {
      defaults.bool(forKey: Keys.agentMode)
    }
    set {
      guard newValue != agentMode else { return }
      defaults.set(newValue, forKey: Keys.agentMode)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

  // MARK: - Extra Server Arguments

  /// Extra `llama serve` CLI arguments -- an unadvertised escape hatch for
  /// server flags the app doesn't expose (e.g. a CORS proxy flag, `--api-key`,
  /// KV-cache quantization). Set via defaults; there's deliberately no UI yet:
  ///   `defaults write app.llama.Llama extraServerArgs -string "--api-key secret"`
  ///   `defaults delete app.llama.Llama extraServerArgs` → none
  /// Tokenized by splitting on whitespace, so `--flag value` works naturally;
  /// no shell is involved in launching the server, so there's no quoting layer
  /// -- each token is passed verbatim as its own argv element. Takes effect on
  /// the next server start (no change notification for external defaults
  /// writes). Security note: this must never become settable from a deeplink
  /// or any other externally-triggerable path, or a webpage could inject
  /// server arguments via the URL scheme.
  static var extraServerArgList: [String] {
    guard let raw = defaults.string(forKey: Keys.extraServerArgs) else { return [] }
    return raw.split(whereSeparator: \.isWhitespace).map(String.init)
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
      guard let path = defaults.string(forKey: Keys.hfCacheDirectory) else {
        return defaultHFCacheDirectory
      }
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    set {
      if newValue == defaultHFCacheDirectory {
        defaults.removeObject(forKey: Keys.hfCacheDirectory)
      } else {
        defaults.set(newValue.path, forKey: Keys.hfCacheDirectory)
      }
      // Ensure the chosen directory exists so the first scan/download after a
      // change doesn't race its creation. (Download paths also create their
      // own subdirs with intermediates, so this is belt-and-braces.)
      try? FileManager.default.createDirectory(
        at: newValue, withIntermediateDirectories: true)
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
