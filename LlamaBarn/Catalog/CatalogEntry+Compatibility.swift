import Foundation

extension CatalogEntry {
  // MARK: - Memory Calculations

  /// We evaluate compatibility assuming a 4k-token context, which is the
  /// default llama.cpp launches with when no explicit value is provided.
  static let compatibilityCtxWindowTokens: Double = 4_096

  /// Models must support at least this context length to launch.
  static let minimumCtxWindowTokens: Double = compatibilityCtxWindowTokens

  static func availableMemoryFraction(forSystemMemoryMb systemMemoryMb: UInt64) -> Double {
    return UserSettings.memoryUsageCap
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

    let defaultContext =
      maximizeContext
      ? ctxWindow
      : {
        let setting = UserSettings.defaultContextWindow
        return setting == .max ? ctxWindow : (setting.rawValue * 1024)
      }()
    var effectiveDesired = desiredTokens.flatMap { $0 > 0 ? $0 : nil } ?? defaultContext

    // Cap desired context if env var is set
    if let maxCtxStr = ProcessInfo.processInfo.environment["BARN_MAX_CTX_K"],
      let maxCtxK = Int(maxCtxStr), maxCtxK > 0
    {
      effectiveDesired = min(effectiveDesired, maxCtxK * 1_024)
    }

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

  /// Calculates available memory budget in MB based on system memory
  private static func memoryBudget(systemMemoryMb: UInt64) -> Double {
    let memoryFraction = availableMemoryFraction(forSystemMemoryMb: systemMemoryMb)
    return Double(systemMemoryMb) * memoryFraction
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
      return CompatibilityInfo(isCompatible: false, incompatibilitySummary: nil)
    }

    let sysMem = SystemMemory.memoryMb
    let estimatedMemoryUsageMb = runtimeMemoryUsageMb(
      ctxWindowTokens: ctxWindowTokens)

    func memoryRequirementSummary() -> String {
      let memoryFraction = Self.availableMemoryFraction(forSystemMemoryMb: sysMem)
      let requiredTotalMb = UInt64(ceil(Double(estimatedMemoryUsageMb) / memoryFraction))
      let gb = ceil(Double(requiredTotalMb) / 1024.0)
      return String(format: "requires %.0f GB+ of memory", gb)
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

  private struct CompatibilityInfo {
    let isCompatible: Bool
    let incompatibilitySummary: String?
  }
}
