import Foundation

extension Notification.Name {
  static let LBServerStateDidChange = Notification.Name("LBServerStateDidChange")
  static let LBServerMemoryDidChange = Notification.Name("LBServerMemoryDidChange")
  static let LBModelDownloadsDidChange = Notification.Name("LBModelDownloadsDidChange")
  static let LBModelDownloadedListDidChange = Notification.Name("LBModelDownloadedListDidChange")
  static let LBModelDownloadFinished = Notification.Name("LBModelDownloadFinished")
  static let LBUserSettingsDidChange = Notification.Name("LBUserSettingsDidChange")
}
