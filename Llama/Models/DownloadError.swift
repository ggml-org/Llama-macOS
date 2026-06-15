import Foundation

/// Describes errors that can occur before a model download begins.
enum DownloadError: Error, LocalizedError {
  case notCompatible(reason: String)
  case notEnoughDiskSpace(required: String, available: String)

  var errorDescription: String? {
    switch self {
    case .notCompatible:
      return "Model Not Compatible"
    case .notEnoughDiskSpace:
      return "Not Enough Disk Space"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .notCompatible(let reason):
      return "This model \(reason). Choose a smaller model or upgrade your system memory."
    case .notEnoughDiskSpace(let required, let available):
      return
        "This model requires \(required) of free space, but only \(available) is available. Please free up some space."
    }
  }
}
