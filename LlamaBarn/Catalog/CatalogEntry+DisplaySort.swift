import Foundation

// Shared comparator for consistent model ordering in menus.
extension CatalogEntry {
  /// Groups models by family, then by model size (e.g., 2B, 4B), then full-precision before quantized variants.
  /// Used for both installed and available models lists to keep related models together.
  static func displayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    if lhs.family != rhs.family { return lhs.family < rhs.family }
    if lhs.paramCountB != rhs.paramCountB { return lhs.paramCountB < rhs.paramCountB }
    if lhs.isFullPrecision != rhs.isFullPrecision { return lhs.isFullPrecision }
    return lhs.id < rhs.id
  }
}
