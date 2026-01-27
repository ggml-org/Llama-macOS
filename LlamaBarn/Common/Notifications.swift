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
}
