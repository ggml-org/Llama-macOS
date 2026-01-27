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

  var label: String {
    switch self {
    case .k4: return "4k"
    case .k8: return "8k"
    case .k16: return "16k"
    case .k32: return "32k"
    case .k64: return "64k"
    case .k128: return "128k"
    case .k256: return "256k"
    }
  }

  var suffix: String {
    ":\(label)"
  }

  static func < (lhs: ContextTier, rhs: ContextTier) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  /// The fixed base tiers that are always considered (when compatible).
  /// 4K for chat/scripts, 32K for basic agents.
  static let baseTiers: [ContextTier] = [.k4, .k32]
}
