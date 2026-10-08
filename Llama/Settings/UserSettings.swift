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

    /// Whether this option only exists in DEBUG builds (flagged in the UI)
    var isDebugOnly: Bool {
      #if DEBUG
        return self == .thirtySec
      #else
        return false
      #endif
    }
  }

  private enum Keys {
    static let hasSeenWelcome = "hasSeenWelcome"
    static let hasSetDefaultLaunchAtLogin = "hasSetDefaultLaunchAtLogin"
    static let exposeToNetwork = "exposeToNetwork"
    static let exposeToNetworkFingerprint = "exposeToNetworkFingerprint"
    static let serverPort = "serverPort"
    static let sleepIdleTime = "sleepIdleTime"
    static let selectedCtxTiers = "selectedCtxTiers"
    static let extraServerArgs = "extraServerArgs"
    static let agentMode = "agentMode"
    static let hfCacheDirectory = "hfCacheDirectory"
    static let hfToken = "hfToken"
    static let modelLastUsedDates = "modelLastUsedDates"
    static let useFullWorkingSet = "useFullWorkingSet"
    static let globalInputShortcut = "globalInputShortcut"
    static let customWebUIDirectory = "customWebUIDirectory"
    static let modelAliases = "modelAliases"
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

  /// Whether a model may use the whole GPU working set, rather than leaving
  /// llama.cpp's fit slack unspent. Off unless explicitly set:
  ///   `defaults write app.llama.Llama useFullWorkingSet -bool true`
  ///
  /// Worth a gigabyte, which is the difference for a model that lands just
  /// over the default line -- a 20B MXFP4 model on a 16 GB Mac, say. The slack
  /// covers what the memory estimate can't see, so spending it means a load
  /// that fits on paper can still fail, or a second model briefly resident
  /// during a swap can push things over. That's a fine bet for someone who
  /// knows their model works, and a bad default for everyone else.
  ///
  /// Note what this deliberately doesn't do: exceed what Metal recommends.
  /// Allocations past the working set do succeed, with macOS swapping to cover
  /// them, so a bigger override is possible -- but nobody has yet shown a
  /// model that runs acceptably there, and "technically loads" isn't the same
  /// as "works".
  ///
  /// It does nothing on an 8 GB Mac, where the RAM floor governs either way --
  /// pushing past it there wedges the machine rather than merely slowing it.
  ///
  /// Undocumented on purpose: it's a probe. If people keep asking for it, that
  /// argues for a real affordance; silence argues for leaving it alone.
  static var useFullWorkingSet: Bool {
    defaults.bool(forKey: Keys.useFullWorkingSet)
  }

  /// The key combo that opens the global-input capture panel, or `nil` when no
  /// shortcut is set -- the default. We ship no default combo on purpose: any
  /// choice would silently claim a system-wide key from whatever the user
  /// already has bound to it. Stored as a `[keyCode, modifiers]` dict of the
  /// same Carbon values `GlobalHotkey.Combo` carries. The setter posts
  /// `LBGlobalInputShortcutDidChange` so the controller re-registers the
  /// hotkey immediately -- no relaunch needed.
  static var globalInputShortcut: GlobalHotkey.Combo? {
    get {
      guard let dict = defaults.dictionary(forKey: Keys.globalInputShortcut),
        let keyCode = dict["keyCode"] as? Int,
        let modifiers = dict["modifiers"] as? Int
      else { return nil }
      return GlobalHotkey.Combo(keyCode: keyCode, modifiers: modifiers)
    }
    set {
      guard newValue != globalInputShortcut else { return }
      if let newValue {
        defaults.set(
          ["keyCode": newValue.keyCode, "modifiers": newValue.modifiers],
          forKey: Keys.globalInputShortcut)
      } else {
        defaults.removeObject(forKey: Keys.globalInputShortcut)
      }
      NotificationCenter.default.post(name: .LBGlobalInputShortcutDidChange, object: nil)
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

  /// Who can reach the server -- the Settings-facing reading of
  /// `networkBindAddress`.
  ///
  /// The two exposed cases are not two flavours of the same thing. `.tailscale`
  /// is reachable from the user's own devices anywhere and invisible on the
  /// local wifi; `.localNetwork` is the reverse -- everyone on this wifi, and
  /// only while you're on it. Tailscale also authenticates and encrypts, which
  /// this server cannot, so where both are possible it's the better answer.
  enum NetworkAccess: Hashable {
    /// Loopback only. The default.
    case off
    /// Bound to a Tailscale address. Stays this case while Tailscale is
    /// signed out and the address is gone: it records what the user chose,
    /// and the server falls back to loopback on its own until it returns.
    case tailscale
    /// Bound to `0.0.0.0` -- anyone on the current network.
    case localNetwork
    /// A hand-set address (`defaults write ... -string`) that isn't the
    /// current Tailscale one. Not offered in the UI, but represented so the
    /// UI never reports "off" while the server is in fact bound somewhere.
    case custom(String)
  }

  static var networkAccess: NetworkAccess {
    guard let address = networkBindAddress else { return .off }
    if address == "0.0.0.0" { return .localNetwork }
    if TailscaleInterface.isTailscaleAddress(address) { return .tailscale }
    return .custom(address)
  }

  /// Applies a choice from the UI. `.custom` is deliberately not settable --
  /// it exists to describe what's already there, not to be chosen.
  static func setNetworkAccess(_ access: NetworkAccess) {
    guard access != networkAccess else { return }

    switch access {
    case .off:
      defaults.removeObject(forKey: Keys.exposeToNetwork)
      exposeToNetworkFingerprint = nil

    case .localNetwork:
      defaults.set(true, forKey: Keys.exposeToNetwork)
      // Remember which network this was agreed to on, so joining a different
      // one can withdraw it (see `NetworkIdentity`).
      exposeToNetworkFingerprint = NetworkIdentity.currentFingerprint()

    case .tailscale:
      // Only reachable from a UI that found an address to offer; if Tailscale
      // went away in between, do nothing rather than store a dead address.
      guard let address = TailscaleInterface.address() else { return }
      defaults.set(address, forKey: Keys.exposeToNetwork)
      // A Tailscale bind isn't tied to a place, so there's no network to scope
      // it to -- see `NetworkExposureGuard`.
      exposeToNetworkFingerprint = nil

    case .custom:
      return
    }

    NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
  }

  /// Fingerprint of the network `exposeToNetwork` was last switched on for.
  /// Nil when exposure is off, or when it was turned on with no default route
  /// to identify (in which case there's nothing to compare against later).
  static var exposeToNetworkFingerprint: String? {
    get {
      defaults.string(forKey: Keys.exposeToNetworkFingerprint)
    }
    set {
      if let newValue {
        defaults.set(newValue, forKey: Keys.exposeToNetworkFingerprint)
      } else {
        defaults.removeObject(forKey: Keys.exposeToNetworkFingerprint)
      }
    }
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

  // MARK: - Custom Web App

  /// A folder the server serves at `/` in place of the built-in web UI
  /// (`--path`), or `nil` for the built-in one -- the default. Lets a web app
  /// of your own ride on the server: same origin as the API, so it needs no
  /// port or CORS setup, and it's up whenever the app is and reachable
  /// wherever network access says the server is.
  ///
  /// Records the choice even if the folder later goes away; the server then
  /// falls back to the built-in UI on its own (see
  /// `LlamaServer.effectiveWebUIDirectory`). The setter posts the settings
  /// change notification, which restarts the server with/without `--path`.
  static var customWebUIDirectory: URL? {
    get {
      defaults.string(forKey: Keys.customWebUIDirectory)
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    set {
      guard newValue?.path != customWebUIDirectory?.path else { return }
      if let newValue {
        defaults.set(newValue.path, forKey: Keys.customWebUIDirectory)
      } else {
        defaults.removeObject(forKey: Keys.customWebUIDirectory)
      }
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }

  // MARK: - Model Aliases

  /// Names API clients can use in place of a model id, each pointed at one
  /// model on this Mac (see `ModelAlias`). In the order they were added,
  /// which is the order Settings lists them in.
  ///
  /// Stored as `[{name, model}]` dicts rather than a name -> model dictionary
  /// so that order survives. An alias whose model was deleted is kept: it
  /// records what the user chose, and it resolves again if the model comes
  /// back. Until then it's simply left out of `models.ini`.
  ///
  /// The setter posts the settings change notification, which regenerates
  /// `models.ini` and restarts the server. A restart rather than the router's
  /// in-place reload, because that reload doesn't update the aliases of a
  /// model that's running -- a switch to or from a loaded model would
  /// silently not take effect until it unloaded.
  static var modelAliases: [ModelAlias] {
    get {
      let raw = defaults.array(forKey: Keys.modelAliases) as? [[String: String]] ?? []
      return raw.compactMap { dict in
        guard let name = dict["name"], let modelId = dict["model"] else { return nil }
        return ModelAlias(name: name, modelId: modelId)
      }
    }
    set {
      guard newValue != modelAliases else { return }
      defaults.set(
        newValue.map { ["name": $0.name, "model": $0.modelId] }, forKey: Keys.modelAliases)
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
