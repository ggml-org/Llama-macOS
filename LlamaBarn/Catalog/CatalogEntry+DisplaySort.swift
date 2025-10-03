import Foundation

// Shared comparator for consistent model ordering in menus.
extension CatalogEntry {
  /// Sorts smaller download sizes first; tie-break by ID for stable ordering.
  static func displayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    if lhs.fileSize != rhs.fileSize { return lhs.fileSize < rhs.fileSize }
    return lhs.id < rhs.id
  }

  /// Orders catalog entries for display within a family submenu.
  /// Sorts by parameter size (ignoring quantization), then full-precision before quantized.
  static func familyDisplayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    // Sort by parameter size first (e.g., E2B before E4B, regardless of quantization)
    if lhs.size != rhs.size { return lhs.size < rhs.size }
    // Within same size, full-precision comes before quantized
    if lhs.isFullPrecision != rhs.isFullPrecision { return lhs.isFullPrecision }
    // Tie-break by file size (smaller quantized variants first)
    return displayOrder(lhs, rhs)
  }
}
