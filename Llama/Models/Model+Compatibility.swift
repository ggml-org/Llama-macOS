import Foundation

extension Model {
  // MARK: - Memory Calculations

  /// We evaluate compatibility assuming a 4k-token context, which is the
  /// default llama.cpp launches with when no explicit value is provided.
  /// Models must also support at least this context length to launch.
  static let compatibilityCtxWindowTokens: Double = 4_096

  /// Memory overhead reserved for macOS and other apps (in MB).
  /// This margin is also passed to llama-server via --fit-target so both
  /// Llama's predictions and llama-server's runtime checks use the same value.
  static let memOverheadMb: Double = 2048

  /// Calculates available memory budget in MB based on system memory.
  /// Formula: totalRAM * 0.75 - overhead
  static func memoryBudget(systemMemoryMb: UInt64) -> Double {
    let totalMb = Double(systemMemoryMb)
    return max(totalMb * 0.75 - memOverheadMb, 0)
  }

  /// Rough pre-download fit check used by the deeplink resolver and the
  /// Discover picks: model weight memory ≈ fileSize × 1.05 must be within
  /// budget. Unknown sizes pass — don't filter out. The real compatibility
  /// check runs at launch once the MemProfile probe has measured resident bytes.
  static func estimatedWeightFits(bytes: Int64?, budgetMb: Double) -> Bool {
    guard let bytes, bytes > 0 else { return true }
    let weightMb = Double(bytes) / 1_048_576.0 * 1.05
    return weightMb <= budgetMb
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
    let weightMb = weightMemoryMb
    let ctxMultiplier = ctxWindowTokens / 1_000.0
    let ctxBytes = Double(ctxBytesPer1kTokens) * ctxMultiplier
    let ctxMb = ctxBytes / 1_048_576.0
    let totalMb = weightMb + ctxMb
    return UInt64(ceil(totalMb))
  }

  // MARK: - Private Helpers

  /// Converts bytes to megabytes using binary units (1 MB = 2^20 bytes)
  private static func bytesToMb(_ bytes: Int64) -> Double {
    Double(bytes) / 1_048_576.0
  }

  /// Weight memory (MB) used by compatibility math.
  /// Prefers the measured `residentBytes` (correct for MoE models). Falls
  /// back to `fileSize * overheadMultiplier` when the MemProfile probe
  /// hasn't landed yet (pre-download placeholders).
  private var weightMemoryMb: Double {
    if residentBytes > 0 {
      return Double(residentBytes) / 1_048_576.0
    }
    let fileSizeMb = Self.bytesToMb(fileSize)
    return fileSizeMb * overheadMultiplier
  }

  /// Computes compatibility info for a model
  private func compatibilityInfo(
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> CompatibilityInfo {
    if Double(ctxWindow) < Self.compatibilityCtxWindowTokens {
      return CompatibilityInfo(
        isCompatible: false,
        incompatibilitySummary: "requires models with ≥4k context"
      )
    }

    if ctxWindowTokens > 0 && ctxWindowTokens > Double(ctxWindow) {
      // Model's native context window is smaller than requested
      let maxLabel = nativeMaxTier?.label ?? "\(ctxWindow / 1024)k"
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
  /// Shows all standard tiers (4K through 128K) that are compatible, plus 256K if supported.
  /// When the MemProfile probe is still pending (or failed), returns only 4K as a safe
  /// default — without `ctxBytesPer1kTokens`, memory estimates are artificially low and
  /// all tiers would falsely appear compatible.
  var supportedContextTiers: [ContextTier] {
    if ctxBytesPer1kTokens <= 0 {
      return [.k4]
    }

    // Filter standard tiers to those compatible with this device
    var tiers = ContextTier.standardTiers.filter { tier in
      isCompatible(ctxWindowTokens: Double(tier.rawValue))
    }

    // Add 256K tier if compatible and not already included
    if isCompatible(ctxWindowTokens: Double(ContextTier.k256.rawValue)),
      !tiers.contains(.k256)
    {
      tiers.append(.k256)
    }

    return tiers.sorted()
  }

  /// The largest standard tier that fits within the model's native context window.
  /// Independent of device RAM -- this is the model's spec ceiling.
  var nativeMaxTier: ContextTier? {
    ContextTier.allCases.last { $0.rawValue <= ctxWindow }
  }

  /// The effective context tier for this model.
  /// Returns user's selection if set and still compatible, otherwise 4K.
  var effectiveCtxTier: ContextTier? {
    let supported = supportedContextTiers
    guard !supported.isEmpty else { return nil }

    // Check if user has a saved preference that's still valid
    if let selected = UserSettings.selectedCtxTier(for: id),
      supported.contains(selected)
    {
      return selected
    }

    return .k4
  }

  private struct CompatibilityInfo {
    let isCompatible: Bool
    let incompatibilitySummary: String?
  }
}
