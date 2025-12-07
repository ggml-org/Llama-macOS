import Foundation

/// Static catalog of available AI models with their configurations and metadata
enum Catalog {

  // MARK: - Data Structures

  struct ModelFamily {
    let name: String  // e.g. "Qwen3 2507"
    let series: String  // e.g. "qwen"
    let serverArgs: [String]?  // optional defaults for all models/builds
    let overheadMultiplier: Double  // overhead multiplier for file size
    let sizes: [ModelSize]

    init(
      name: String,
      series: String,
      serverArgs: [String]? = nil,
      overheadMultiplier: Double = 1.05,
      sizes: [ModelSize]
    ) {
      self.name = name
      self.series = series
      self.serverArgs = serverArgs
      self.overheadMultiplier = overheadMultiplier
      self.sizes = sizes.sorted { $0.parameterCount < $1.parameterCount }
    }

    var iconName: String {
      "ModelLogos/\(series.lowercased())"
    }

    var allModels: [CatalogEntry] {
      sizes.flatMap { size in
        ([size.build] + size.quantizedBuilds).map { build in
          Catalog.entry(family: self, size: size, build: build)
        }
      }
    }

    func selectableModels(preferQuantized: Bool) -> [CatalogEntry] {
      let compatibleModels = allModels.filter { Catalog.isModelCompatible($0) }

      // Group by size (e.g., "27B") to pick the preferred version
      let modelsBySize = Dictionary(grouping: compatibleModels, by: { $0.size })

      return modelsBySize.values.compactMap { models in
        bestModel(in: models, preferQuantized: preferQuantized)
      }.sorted(by: CatalogEntry.displayOrder(_:_:))
    }

    private func bestModel(in models: [CatalogEntry], preferQuantized: Bool) -> CatalogEntry? {
      if preferQuantized {
        // Prefer quantized, fallback to full precision
        return models.first(where: { !$0.isFullPrecision })
          ?? models.first(where: { $0.isFullPrecision })
      } else {
        // Prefer full precision, fallback to quantized
        return models.first(where: { $0.isFullPrecision })
          ?? models.first(where: { !$0.isFullPrecision })
      }
    }
  }

  struct ModelSize {
    let name: String  // e.g. "4B", "30B"
    let parameterCount: Int64  // Total model parameters
    let releaseDate: Date
    let ctxWindow: Int
    /// Estimated KV-cache bytes needed for a 1k-token context.
    let ctxBytesPer1kTokens: Int
    let serverArgs: [String]?  // optional defaults for all builds
    let mmproj: URL?  // optional vision projection file for multimodal models
    let build: ModelBuild
    let quantizedBuilds: [ModelBuild]

    init(
      name: String,
      parameterCount: Int64,
      releaseDate: Date,
      ctxWindow: Int,
      ctxBytesPer1kTokens: Int,
      serverArgs: [String]? = nil,
      mmproj: URL? = nil,
      build: ModelBuild,
      quantizedBuilds: [ModelBuild] = []
    ) {
      self.name = name
      self.parameterCount = parameterCount
      self.releaseDate = releaseDate
      self.ctxWindow = ctxWindow
      self.ctxBytesPer1kTokens = ctxBytesPer1kTokens
      self.serverArgs = serverArgs
      self.mmproj = mmproj
      self.build = build
      self.quantizedBuilds = quantizedBuilds
    }
  }

  struct ModelBuild {
    let id: String  // unique identifier
    let quantization: String
    let fileSize: Int64
    let downloadUrl: URL
    let additionalParts: [URL]?
    let serverArgs: [String]?

    init(
      id: String,
      quantization: String,
      fileSize: Int64,
      downloadUrl: URL,
      additionalParts: [URL]? = nil,
      serverArgs: [String]? = nil
    ) {
      self.id = id
      self.quantization = quantization
      self.fileSize = fileSize
      self.downloadUrl = downloadUrl
      self.additionalParts = additionalParts
      self.serverArgs = serverArgs
    }
  }

  // MARK: - Public Data

  // MARK: - Public Accessors

  /// Returns all catalog entries by traversing the hierarchy
  static func allModels() -> [CatalogEntry] {
    families.flatMap { $0.allModels }
  }

  /// Finds a catalog entry by ID by traversing the hierarchy
  static func findModel(id: String) -> CatalogEntry? {
    allModels().first { $0.id == id }
  }

  // MARK: - Memory Calculations

  /// Fraction of system memory available for models on standard configurations.
  /// Macs with ≥128 GB of RAM can safely allocate 75% to the model since they retain ample headroom.
  private static let defaultAvailableMemoryFraction: Double = 0.5
  private static let highMemoryAvailableFraction: Double = 0.75
  private static let highMemoryThresholdMb: UInt64 = 128 * 1024  // binary units to match SystemMemory

  /// We evaluate compatibility assuming a 4k-token context, which is the
  /// default llama.cpp launches with when no explicit value is provided.
  static let compatibilityCtxWindowTokens: Double = 4_096

  /// Models must support at least this context window to launch.
  static let minimumCtxWindowTokens: Double = compatibilityCtxWindowTokens

  static func availableMemoryFraction(forSystemMemoryMb systemMemoryMb: UInt64) -> Double {
    guard systemMemoryMb >= highMemoryThresholdMb else { return defaultAvailableMemoryFraction }
    return highMemoryAvailableFraction
  }

  static func usableCtxWindow(
    for model: CatalogEntry,
    desiredTokens: Int? = nil,
    maximizeContext: Bool = false
  ) -> Int? {
    let minimumTokens = Int(minimumCtxWindowTokens)
    guard model.ctxWindow >= minimumTokens else { return nil }

    let sysMem = SystemMemory.memoryMb
    guard sysMem > 0 else { return nil }

    let budgetMb = memoryBudget(systemMemoryMb: sysMem)
    let fileSizeWithOverheadMb = fileSizeWithOverhead(for: model)
    if fileSizeWithOverheadMb > budgetMb { return nil }

    let defaultContext = maximizeContext ? model.ctxWindow : Int(compatibilityCtxWindowTokens)
    var effectiveDesired = desiredTokens.flatMap { $0 > 0 ? $0 : nil } ?? defaultContext

    // Cap desired context if env var is set
    if let maxCtxStr = ProcessInfo.processInfo.environment["BARN_MAX_CTX_K"],
      let maxCtxK = Int(maxCtxStr), maxCtxK > 0
    {
      effectiveDesired = min(effectiveDesired, maxCtxK * 1_024)
    }

    let desiredTokensDouble = Double(effectiveDesired)

    let ctxBytesPerToken = Double(model.ctxBytesPer1kTokens) / 1_000.0
    let maxTokensFromMemory: Double = {
      if ctxBytesPerToken <= 0 {
        return Double(model.ctxWindow)
      }
      let remainingMb = budgetMb - fileSizeWithOverheadMb
      if remainingMb <= 0 { return 0 }
      let remainingBytes = remainingMb * 1_048_576.0
      return remainingBytes / ctxBytesPerToken
    }()

    let cappedTokens = min(Double(model.ctxWindow), desiredTokensDouble, maxTokensFromMemory)
    if cappedTokens < minimumCtxWindowTokens { return nil }

    let floored = Int(cappedTokens)
    var rounded = floored
    if rounded < minimumTokens { rounded = minimumTokens }
    if rounded > model.ctxWindow { rounded = model.ctxWindow }

    return rounded
  }

  static func isModelCompatible(
    _ model: CatalogEntry,
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> Bool {
    compatibilityInfo(for: model, ctxWindowTokens: ctxWindowTokens).isCompatible
  }

  static func incompatibilitySummary(
    _ model: CatalogEntry,
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> String? {
    compatibilityInfo(for: model, ctxWindowTokens: ctxWindowTokens).incompatibilitySummary
  }

  static func runtimeMemoryUsageMb(
    for model: CatalogEntry,
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> UInt64 {
    // Memory calculations use binary units so they line up with Activity Monitor.
    let fileSizeWithOverheadMb = fileSizeWithOverhead(for: model)
    let ctxMultiplier = ctxWindowTokens / 1_000.0
    let ctxBytes = Double(model.ctxBytesPer1kTokens) * ctxMultiplier
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
  private static func fileSizeWithOverhead(for model: CatalogEntry) -> Double {
    let fileSizeMb = bytesToMb(model.fileSize)
    return fileSizeMb * model.overheadMultiplier
  }

  /// Calculates available memory budget in MB based on system memory
  private static func memoryBudget(systemMemoryMb: UInt64) -> Double {
    let memoryFraction = availableMemoryFraction(forSystemMemoryMb: systemMemoryMb)
    return Double(systemMemoryMb) * memoryFraction
  }

  /// Computes compatibility info for a model
  private static func compatibilityInfo(
    for model: CatalogEntry,
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> CompatibilityInfo {
    let minimumTokens = minimumCtxWindowTokens

    if Double(model.ctxWindow) < minimumTokens {
      return CompatibilityInfo(
        isCompatible: false,
        incompatibilitySummary: "requires models with ≥4k context"
      )
    }

    if ctxWindowTokens > 0 && ctxWindowTokens > Double(model.ctxWindow) {
      return CompatibilityInfo(isCompatible: false, incompatibilitySummary: nil)
    }

    let sysMem = SystemMemory.memoryMb
    let estimatedMemoryUsageMb = runtimeMemoryUsageMb(
      for: model, ctxWindowTokens: ctxWindowTokens)

    func memoryRequirementSummary() -> String {
      let memoryFraction = availableMemoryFraction(forSystemMemoryMb: sysMem)
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

    let budgetMb = memoryBudget(systemMemoryMb: sysMem)
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

  /// Builds a CatalogEntry from hierarchy components
  static func entry(family: ModelFamily, size: ModelSize, build: ModelBuild)
    -> CatalogEntry
  {
    let effectiveArgs =
      (family.serverArgs ?? []) + (size.serverArgs ?? []) + (build.serverArgs ?? [])

    let isFullPrecision = build.id == size.build.id

    return CatalogEntry(
      id: build.id,
      family: family.name,
      parameterCount: size.parameterCount,
      size: size.name,
      ctxWindow: size.ctxWindow,
      fileSize: build.fileSize,
      ctxBytesPer1kTokens: size.ctxBytesPer1kTokens,
      overheadMultiplier: family.overheadMultiplier,
      downloadUrl: build.downloadUrl,
      additionalParts: build.additionalParts,
      mmprojUrl: size.mmproj,
      serverArgs: effectiveArgs,
      icon: family.iconName,
      quantization: build.quantization,
      isFullPrecision: isFullPrecision
    )
  }

}
