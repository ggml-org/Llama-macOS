import Foundation

enum AppInfo {
  static var shortVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }

  static var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
  }

  /// Checks for `LB_DEBUG_UI` environment variable to enable visual layout debugging
  static var isUIDebugEnabled: Bool {
    ProcessInfo.processInfo.environment["LB_DEBUG_UI"] != nil
  }
}
