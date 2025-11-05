import Foundation

/// Simple disk space helpers scoped to the volume hosting our models folder.
enum DiskSpace {
  /// Returns available bytes on the volume for important usage (macOS 10.13+),
  /// falling back to general available capacity if needed. Returns 0 on failure.
  static func availableBytes(at url: URL) -> Int64 {
    do {
      let values = try url.resourceValues(
        forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
      if let important = values.volumeAvailableCapacityForImportantUsage {
        return important
      }
      if let general = values.volumeAvailableCapacity {
        return Int64(general)
      }
    } catch {
      // Ignore and return 0 below
    }
    return 0
  }

  /// Formats a byte count in decimal GB for concise UI.
  static func formatGB(_ bytes: Int64) -> String {
    Format.gigabytes(bytes)
  }
}
