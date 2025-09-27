import Foundation

/// Hugging Face api
/// - https://huggingface.co/api/models/{organization}/{model-name} -- model details
/// - https://huggingface.co/api/models?author={organization}&search={query} -- search based on author and query

/// Static catalog of available AI models with their configurations and metadata
enum ModelCatalog {

  /// Fraction of system memory available for models on standard configurations.
  /// Macs with ≥128 GB of RAM can safely allocate 75% to the model since they retain ample headroom.
  private static let defaultAvailableMemoryFraction: Double = 0.5
  private static let highMemoryAvailableFraction: Double = 0.75
  private static let highMemoryThresholdMB: UInt64 = 128 * 1024  // binary units to match SystemMemory

  static func availableMemoryFraction(forSystemMemoryMB systemMemoryMB: UInt64) -> Double {
    guard systemMemoryMB >= highMemoryThresholdMB else { return defaultAvailableMemoryFraction }
    return highMemoryAvailableFraction
  }

  /// We evaluate compatibility assuming a 4k-token context, which is the
  /// default llama.cpp launches with when no explicit value is provided.
  static let compatibilityContextLengthTokens: Double = 4_096

  /// Models must support at least this context length to launch.
  static let minimumContextLengthTokens: Double = compatibilityContextLengthTokens

  // MARK: - New hierarchical catalog

  struct ModelBuild {
    let id: String?  // explicit ID for the leaf (preferred)
    let quantization: String
    let isFullPrecision: Bool
    let fileSize: Int64
    /// Estimated KV-cache bytes needed for a 1k-token context.
    let ctxFootprint: Int
    let downloadUrl: URL
    let additionalParts: [URL]?
    let serverArgs: [String]

    func asEntry(family: ModelFamily, model: Model) -> ModelCatalogEntry {
      let effectiveArgs = (family.serverArgs ?? []) + (model.serverArgs ?? []) + serverArgs
      return ModelCatalogEntry(
        id: id
          ?? ModelCatalog.makeId(family: family.name, modelLabel: model.label, build: self),
        family: family.name,
        variant: model.label,
        releaseDate: model.releaseDate,
        contextLength: model.contextLength,
        fileSize: fileSize,
        ctxFootprint: ctxFootprint,
        downloadUrl: downloadUrl,
        additionalParts: additionalParts,
        serverArgs: effectiveArgs,
        icon: family.iconName,
        quantization: quantization,
        isFullPrecision: isFullPrecision
      )
    }
  }

  struct Model {
    let label: String  // e.g. "4B", "30B"
    let releaseDate: Date
    let contextLength: Int
    let serverArgs: [String]?  // optional defaults for all builds
    let build: ModelBuild
    let quantizedBuilds: [ModelBuild]
  }

  struct ModelFamily {
    let name: String  // e.g. "Qwen3 2507"
    let series: String  // e.g. "qwen"
    let blurb: String  // short one- or two-sentence description
    let serverArgs: [String]?  // optional defaults for all models/builds
    let models: [Model]

    init(
      name: String,
      series: String,
      blurb: String,
      serverArgs: [String]? = nil,
      models: [Model]
    ) {
      self.name = name
      self.series = series
      self.blurb = blurb
      self.serverArgs = serverArgs
      self.models = models
    }

    var iconName: String {
      "ModelLogos/\(series.lowercased())"
    }
  }

  /// Families expressed with shared metadata to reduce duplication
  private static let families: [ModelFamily] = ModelCatalogFamilies.families

  // MARK: - ID + flatten helpers

  private static func slug(_ s: String) -> String {
    return
      s
      .lowercased()
      .replacingOccurrences(of: " ", with: "-")
      .replacingOccurrences(of: "/", with: "-")
  }

  /// Preserves existing ID scheme when an explicit build.id is not provided:
  /// - Q8_0 builds use suffix "-q8"
  /// - mxfp4 builds use suffix "-mxfp4"
  /// - other builds omit suffix
  private static func makeId(family: String, modelLabel: String, build: ModelBuild) -> String {
    let familySlug = slug(family)
    let modelSlug = slug(modelLabel)
    var base = "\(familySlug)-\(modelSlug)"
    // DeepSeek R1 legacy IDs included "-qwen3" segment
    if familySlug == "deepseek-r1-0528" {
      base = "\(familySlug)-qwen3-\(modelSlug)"
    }
    let quant = build.quantization.uppercased()
    if quant == "Q8_0" {
      return base + "-q8"
    } else if quant == "MXFP4" {
      return base + "-mxfp4"
    } else {
      return base
    }
  }

  // MARK: - Accessors
  static var uiFamilies: [ModelFamily] {
    filteredFamilies(showQuantizedVariants: UserSettings.showQuantizedVariants)
  }

  private static func filteredFamilies(showQuantizedVariants: Bool) -> [ModelFamily] {
    guard !showQuantizedVariants else { return families }

    return families.map { family in
      var hasQuantizedBuilds = false
      let filteredModels: [Model] = family.models.map { model in
        if !model.quantizedBuilds.isEmpty {
          hasQuantizedBuilds = true
          return Model(
            label: model.label,
            releaseDate: model.releaseDate,
            contextLength: model.contextLength,
            serverArgs: model.serverArgs,
            build: model.build,
            quantizedBuilds: []
          )
        }
        return model
      }

      if hasQuantizedBuilds {
        return ModelFamily(
          name: family.name,
          series: family.series,
          blurb: family.blurb,
          serverArgs: family.serverArgs,
          models: filteredModels
        )
      } else {
        return family
      }
    }
  }

  static func allEntries() -> [ModelCatalogEntry] {
    families.flatMap { family in
      family.models.flatMap { model -> [ModelCatalogEntry] in
        let allBuilds = [model.build] + model.quantizedBuilds
        return allBuilds.map { build in build.asEntry(family: family, model: model) }
      }
    }
  }

  static func entry(forId id: String) -> ModelCatalogEntry? {
    for family in families {
      for model in family.models {
        let allBuilds = [model.build] + model.quantizedBuilds
        for build in allBuilds {
          let entry = build.asEntry(family: family, model: model)
          if entry.id == id { return entry }
        }
      }
    }
    return nil
  }

  /// Gets system memory in MB using shared system memory utility
  static func getSystemMemoryMB() -> UInt64 {
    return SystemMemory.getMemoryMB()
  }

  /// Computes the maximum context length (in tokens) that fits within the allowed memory budget.
  /// - Parameters:
  ///   - model: Catalog entry under evaluation.
  ///   - desiredTokens: Upper bound requested by the caller. When nil, defaults to the model's max.
  /// - Returns: Rounded context length (multiple of 1024) or nil when the model cannot satisfy the
  ///            minimum requirements.
  static func safeContextLength(
    for model: ModelCatalogEntry,
    desiredTokens: Int? = nil
  ) -> Int? {
    let minimumTokens = Int(minimumContextLengthTokens)
    guard model.contextLength >= minimumTokens else { return nil }

    let systemMemoryMB = getSystemMemoryMB()
    guard systemMemoryMB > 0 else { return nil }

    let memoryFraction = availableMemoryFraction(forSystemMemoryMB: systemMemoryMB)
    let availableMemoryMB = Double(systemMemoryMB) * memoryFraction
    let fileSizeMB = Double(model.fileSize) / 1_048_576.0
    if fileSizeMB > availableMemoryMB { return nil }

    let effectiveDesired = desiredTokens.flatMap { $0 > 0 ? $0 : nil } ?? model.contextLength
    let desiredTokensDouble = Double(effectiveDesired)

    let ctxBytesPerToken = Double(model.ctxFootprint) / 1_000.0
    let maxTokensFromMemory: Double = {
      if ctxBytesPerToken <= 0 {
        return Double(model.contextLength)
      }
      let remainingMB = availableMemoryMB - fileSizeMB
      if remainingMB <= 0 { return 0 }
      let remainingBytes = remainingMB * 1_048_576.0
      return remainingBytes / ctxBytesPerToken
    }()

    let cappedTokens = min(Double(model.contextLength), desiredTokensDouble, maxTokensFromMemory)
    if cappedTokens < minimumContextLengthTokens { return nil }

    let floored = Int(cappedTokens)
    var rounded = (floored / 1_024) * 1_024
    if rounded < minimumTokens { rounded = minimumTokens }
    if rounded > model.contextLength { rounded = model.contextLength }
    return rounded
  }

  /// Recommended context length to launch the model with, honoring memory constraints.
  static func recommendedContextLength(for model: ModelCatalogEntry) -> Int? {
    safeContextLength(for: model)
  }

  /// Checks if a model can fit within system memory constraints
  static func isModelCompatible(
    _ model: ModelCatalogEntry,
    contextLengthTokens: Double = compatibilityContextLengthTokens
  ) -> Bool {
    let minimumTokens = minimumContextLengthTokens
    if Double(model.contextLength) < minimumTokens { return false }
    if contextLengthTokens > 0 && contextLengthTokens > Double(model.contextLength) { return false }

    let systemMemoryMB = getSystemMemoryMB()
    guard systemMemoryMB > 0 else { return false }

    let memoryFraction = availableMemoryFraction(forSystemMemoryMB: systemMemoryMB)
    let availableMemoryMB = Double(systemMemoryMB) * memoryFraction
    let estimatedMemoryUsageMB = Double(
      runtimeMemoryUsageMB(for: model, contextLengthTokens: contextLengthTokens))
    return estimatedMemoryUsageMB <= availableMemoryMB
  }

  /// If incompatible, returns a short human-readable reason showing
  /// estimated memory needed (rounded to whole GB).
  /// Example: "needs ~12 GB of mem". Returns nil if compatible.
  static func incompatibilitySummary(
    _ model: ModelCatalogEntry,
    contextLengthTokens: Double = compatibilityContextLengthTokens
  ) -> String? {
    if Double(model.contextLength) < minimumContextLengthTokens {
      return "requires models with ≥4k context"
    }

    let systemMemoryMB = getSystemMemoryMB()
    let memoryFraction = availableMemoryFraction(forSystemMemoryMB: systemMemoryMB)
    let estimatedMemoryUsageMB = runtimeMemoryUsageMB(
      for: model, contextLengthTokens: contextLengthTokens)
    // Compute total RAM required so that our available fraction would fit the model.
    // Round up to avoid under‑specing.
    let requiredTotalMB = UInt64(ceil(Double(estimatedMemoryUsageMB) / memoryFraction))
    func gbStringCeilPlus(_ mb: UInt64) -> String {
      let gb = ceil(Double(mb) / 1024.0)
      return String(format: "%.0f GB+", gb)
    }

    // If we can't detect system memory, still show the total needed spec.
    if systemMemoryMB == 0 {
      return "requires \(gbStringCeilPlus(requiredTotalMB)) of memory"
    }

    let availableMemoryMB = UInt64(Double(systemMemoryMB) * memoryFraction)
    if estimatedMemoryUsageMB <= availableMemoryMB { return nil }

    return "requires \(gbStringCeilPlus(requiredTotalMB)) of memory"
  }

  static func runtimeMemoryUsageMB(
    for model: ModelCatalogEntry,
    contextLengthTokens: Double = compatibilityContextLengthTokens
  ) -> UInt64 {
    // Memory calculations use binary units so they line up with Activity Monitor.
    let fileSizeMB = Double(model.fileSize) / 1_048_576.0
    let contextMultiplier = contextLengthTokens / 1_000.0
    let ctxBytes = Double(model.ctxFootprint) * contextMultiplier
    let ctxMB = ctxBytes / 1_048_576.0
    let totalMB = fileSizeMB + ctxMB
    return UInt64(ceil(totalMB))
  }

}
