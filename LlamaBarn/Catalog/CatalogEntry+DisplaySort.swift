import Foundation

// Shared comparator for consistent model ordering in menus.
extension CatalogEntry {
  /// Groups models by family, then sorts by size within each family.
  /// Used for both installed and available models lists to keep related models together.
  static func displayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    if lhs.family != rhs.family { return lhs.family < rhs.family }
    if lhs.fileSize != rhs.fileSize { return lhs.fileSize < rhs.fileSize }
    return lhs.id < rhs.id
  }
}
