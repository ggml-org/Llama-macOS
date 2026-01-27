import Foundation

extension CatalogEntry {
  // MARK: - Memory Calculations

  /// We evaluate compatibility assuming a 4k-token context, which is the
  /// default llama.cpp launches with when no explicit value is provided.
  static let compatibilityCtxWindowTokens: Double = 4_096

  /// Models must support at least this context length to launch.
  static let minimumCtxWindowTokens: Double = compatibilityCtxWindowTokens

  /// Memory overhead reserved for macOS and other apps (in MB).
  /// This margin is also passed to llama-server via --fit-target so both
  /// LlamaBarn's predictions and llama-server's runtime checks use the same value.
  static let memOverheadMb: Double = 2048

  /// Calculates available memory budget in MB based on system memory.
  /// Formula: totalRAM * 0.75 - overhead
  static func memoryBudget(systemMemoryMb: UInt64) -> Double {
    let totalMb = Double(systemMemoryMb)
    return max(totalMb * 0.75 - memOverheadMb, 0)
  }

  func usableCtxWindow(
    desiredTokens: Int? = nil,
    maximizeContext: Bool = false
  ) -> Int? {
    let minimumTokens = Int(Self.minimumCtxWindowTokens)
    guard ctxWindow >= minimumTokens else { return nil }

    let sysMem = SystemMemory.memoryMb
    guard sysMem > 0 else { return nil }

    let budgetMb = Self.memoryBudget(systemMemoryMb: sysMem)
    let fileSizeWithOverheadMb = fileSizeWithOverhead
    if fileSizeWithOverheadMb > budgetMb { return nil }

    // Default to 4k context unless maximizing or explicitly requested
    let defaultContext = maximizeContext ? ctxWindow : minimumTokens
    let effectiveDesired = desiredTokens.flatMap { $0 > 0 ? $0 : nil } ?? defaultContext

    let desiredTokensDouble = Double(effectiveDesired)

    let ctxBytesPerToken = Double(ctxBytesPer1kTokens) / 1_000.0
    let maxTokensFromMemory: Double = {
      if ctxBytesPerToken <= 0 {
        return Double(ctxWindow)
      }
      let remainingMb = budgetMb - fileSizeWithOverheadMb
      if remainingMb <= 0 { return 0 }
      let remainingBytes = remainingMb * 1_048_576.0
      return remainingBytes / ctxBytesPerToken
    }()

    let cappedTokens = min(Double(ctxWindow), desiredTokensDouble, maxTokensFromMemory)
    if cappedTokens < Self.minimumCtxWindowTokens { return nil }

    let floored = Int(cappedTokens)
    var rounded = floored
    if rounded < minimumTokens { rounded = minimumTokens }
    if rounded > ctxWindow { rounded = ctxWindow }

    return rounded
  }

  func isCompatible(
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> Bool {
    compatibilityInfo(ctxWindowTokens: ctxWindowTokens).isCompatible
  }

  func incompatibilitySummary(
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> String? {
    compatibilityInfo(ctxWindowTokens: ctxWindowTokens).incompatibilitySummary
  }

  func runtimeMemoryUsageMb(
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> UInt64 {
    // Memory calculations use binary units so they line up with Activity Monitor.
    let fileSizeWithOverheadMb = fileSizeWithOverhead
    let ctxMultiplier = ctxWindowTokens / 1_000.0
    let ctxBytes = Double(ctxBytesPer1kTokens) * ctxMultiplier
    let ctxMb = ctxBytes / 1_048_576.0
    let totalMb = fileSizeWithOverheadMb + ctxMb
    return UInt64(ceil(totalMb))
  }

  // MARK: - Private Helpers

  /// Converts bytes to megabytes using binary units (1 MB = 2^20 bytes)
  private static func bytesToMb(_ bytes: Int64) -> Double {
    Double(bytes) / 1_048_576.0
  }

  /// Calculates file size in MB including overhead multiplier
  private var fileSizeWithOverhead: Double {
    let fileSizeMb = Self.bytesToMb(fileSize)
    return fileSizeMb * overheadMultiplier
  }

  /// Computes compatibility info for a model
  private func compatibilityInfo(
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> CompatibilityInfo {
    let minimumTokens = Self.minimumCtxWindowTokens

    if Double(ctxWindow) < minimumTokens {
      return CompatibilityInfo(
        isCompatible: false,
        incompatibilitySummary: "requires models with ≥4k context"
      )
    }

    if ctxWindowTokens > 0 && ctxWindowTokens > Double(ctxWindow) {
      // Model's native context window is smaller than requested
      let maxTier = ContextTier.allCases.last { $0.rawValue <= ctxWindow }
      let maxLabel = maxTier?.label ?? "\(ctxWindow / 1024)k"
      return CompatibilityInfo(
        isCompatible: false,
        incompatibilitySummary: "model max is \(maxLabel)"
      )
    }

    let sysMem = SystemMemory.memoryMb
    let estimatedMemoryUsageMb = runtimeMemoryUsageMb(
      ctxWindowTokens: ctxWindowTokens)

    func memoryRequirementSummary() -> String {
      // Reverse the budget formula to find required total RAM:
      // budget = total * 0.75 - overhead => total = (budget + overhead) / 0.75
      let requiredBudgetMb = Double(estimatedMemoryUsageMb)
      let requiredTotalMb = (requiredBudgetMb + Self.memOverheadMb) / 0.75
      let gb = ceil(requiredTotalMb / 1024.0)

      let commonSizes: [Double] = [8, 16, 18, 24, 32, 36, 48, 64, 96, 128, 192]
      let displayGb = commonSizes.first(where: { $0 >= gb }) ?? gb

      return String(format: "Requires a Mac with %.0f GB+ of memory", displayGb)
    }

    guard sysMem > 0 else {
      return CompatibilityInfo(
        isCompatible: false,
        incompatibilitySummary: memoryRequirementSummary()
      )
    }

    let budgetMb = Self.memoryBudget(systemMemoryMb: sysMem)
    let isCompatible = estimatedMemoryUsageMb <= UInt64(budgetMb)

    return CompatibilityInfo(
      isCompatible: isCompatible,
      incompatibilitySummary: isCompatible ? nil : memoryRequirementSummary()
    )
  }

  /// Returns all context tiers that this model can support given device memory constraints.
  /// Uses fixed tiers: 4K, 32K, and max (if >32K).
  /// Only returns tiers that are actually compatible with the device.
  var supportedContextTiers: [ContextTier] {
    // Start with base tiers (4K, 32K) that are compatible
    var tiers = ContextTier.baseTiers.filter { tier in
      isCompatible(ctxWindowTokens: Double(tier.rawValue))
    }

    // Find the max tier this model can run at (must be >32K to be shown separately)
    let maxTier = ContextTier.allCases
      .filter { $0.rawValue > ContextTier.k32.rawValue }
      .filter { isCompatible(ctxWindowTokens: Double($0.rawValue)) }
      .max()

    // Add max tier if it exists and isn't already in the list
    if let maxTier, !tiers.contains(maxTier) {
      tiers.append(maxTier)
    }

    return tiers.sorted()
  }

  private struct CompatibilityInfo {
    let isCompatible: Bool
    let incompatibilitySummary: String?
  }
}
