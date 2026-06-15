import Foundation

extension Notification.Name {
  static let LBServerStateDidChange = Notification.Name("LBServerStateDidChange")
  static let LBServerMemoryDidChange = Notification.Name("LBServerMemoryDidChange")
  static let LBModelDownloadsDidChange = Notification.Name("LBModelDownloadsDidChange")
  static let LBModelDownloadedListDidChange = Notification.Name("LBModelDownloadedListDidChange")
  static let LBUserSettingsDidChange = Notification.Name("LBUserSettingsDidChange")
  static let LBCheckForUpdates = Notification.Name("LBCheckForUpdates")
  static let LBShowSettings = Notification.Name("LBShowSettings")
  static let LBModelDownloadDidFail = Notification.Name("LBModelDownloadDidFail")
  static let LBModelStatusDidChange = Notification.Name("LBModelStatusDidChange")
  // Posted when some background flow wants the menu bar to surface a short
  // speech-bubble hint (e.g. deeplink install started). userInfo["message"]
  // carries the text.
  static let LBShowMenuHint = Notification.Name("LBShowMenuHint")
  // Posted when the app-owned CLI install state changes (idle/installing/failed),
  // so the menu can surface a "setting up…" banner or a retry affordance.
  static let LBCLIInstallStateDidChange = Notification.Name("LBCLIInstallStateDidChange")
  // Posted by the menu's setup banner to re-run the CLI readiness check --
  // retry a failed install, or re-check after the user ran `brew upgrade`.
  static let LBRecheckCLI = Notification.Name("LBRecheckCLI")
}
