import Foundation

/// Represents a context length tier for running models.
/// Fixed tiers: 4K (chat/scripts), 32K (agents), and max supported tier.
enum ContextTier: Int, CaseIterable, Identifiable, Comparable {
  case k4 = 4096
  case k8 = 8192
  case k16 = 16384
  case k32 = 32768
  case k64 = 65536
  case k128 = 131072
  case k256 = 262144

  var id: Int { rawValue }

  /// Number-only label without the "ctx" suffix (e.g. "4k").
  /// Used when composing dual-value labels like "4k of 32k ctx".
  var shortLabel: String { "\(rawValue / 1024)k" }

  var label: String { "\(shortLabel) ctx" }

  var suffix: String {
    ":\(label)"
  }

  static func < (lhs: ContextTier, rhs: ContextTier) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  /// The standard tiers shown in the UI (when compatible).
  static let standardTiers: [ContextTier] = [.k4, .k8, .k16, .k32, .k64, .k128]
}
