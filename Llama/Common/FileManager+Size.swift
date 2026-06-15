import Foundation

extension FileManager {
  /// Returns the size in bytes of the file at `path`, or 0 if it can't be read
  /// (missing file, no size attribute, etc.). Does not resolve symlinks — for
  /// HF-cache symlinks, resolve the path before calling.
  func fileSize(atPath path: String) -> Int64 {
    guard let attrs = try? attributesOfItem(atPath: path) else { return 0 }
    return (attrs[.size] as? NSNumber)?.int64Value ?? 0
  }
}
