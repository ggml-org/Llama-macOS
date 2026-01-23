import Foundation

enum ContextTier: Int, CaseIterable, Identifiable, Comparable {
  case k4 = 4096
  case k32 = 32768
  case k128 = 131072

  var id: Int { rawValue }

  var label: String {
    switch self {
    case .k4: return "4k"
    case .k32: return "32k"
    case .k128: return "128k"
    }
  }

  var suffix: String {
    ":\(label)"
  }

  static func < (lhs: ContextTier, rhs: ContextTier) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
