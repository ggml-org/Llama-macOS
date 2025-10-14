import Foundation

/// Hugging Face api
/// - https://huggingface.co/api/models/{organization}/{model-name} -- model details
/// - https://huggingface.co/api/models?author={organization}&search={query} -- search based on author and query

/// Static catalog of available AI models with their configurations and metadata
enum Catalog {

  /// Fraction of system memory available for models on standard configurations.
  /// Macs with ≥128 GB of RAM can safely allocate 75% to the model since they retain ample headroom.
  private static let defaultAvailableMemoryFraction: Double = 0.5
  private static let highMemoryAvailableFraction: Double = 0.75
  private static let highMemoryThresholdMb: UInt64 = 128 * 1024  // binary units to match SystemMemory

  /// Cache for compatibility checks since model properties and system memory are fixed at launch.
  /// Lives for app lifetime, never invalidated. Cache keys include context length since we check
  /// compatibility at different context windows (default 4k, max context, custom values).
  private struct CompatibilityInfo {
    let isCompatible: Bool
    let incompatibilitySummary: String?
  }

  private struct CompatibilityCacheKey: Hashable {
    let modelId: String
    let tokens: Double
  }

  private struct UsableContextCacheKey: Hashable {
    let modelId: String
    let desiredTokens: Int?
  }

  private static var compatibilityCache: [CompatibilityCacheKey: CompatibilityInfo] = [:]
  private static var usableContextCache: [UsableContextCacheKey: Int?] = [:]

  static func availableMemoryFraction(forSystemMemoryMb systemMemoryMb: UInt64) -> Double {
    guard systemMemoryMb >= highMemoryThresholdMb else { return defaultAvailableMemoryFraction }
    return highMemoryAvailableFraction
  }

  /// We evaluate compatibility assuming a 4k-token context, which is the
  /// default llama.cpp launches with when no explicit value is provided.
  static let compatibilityCtxWindowTokens: Double = 4_096

  /// Models must support at least this context window to launch.
  static let minimumCtxWindowTokens: Double = compatibilityCtxWindowTokens

  // MARK: - New hierarchical catalog

  struct ModelBuild {
    let id: String?  // explicit ID for the leaf (preferred)
    let quantization: String
    let isFullPrecision: Bool
    let fileSize: Int64
    /// Estimated KV-cache bytes needed for a 1k-token context.
    let ctxBytesPer1kTokens: Int
    let downloadUrl: URL
    let additionalParts: [URL]?
    let serverArgs: [String]

    func asEntry(family: ModelFamily, model: Model) -> CatalogEntry {
      let effectiveArgs = (family.serverArgs ?? []) + (model.serverArgs ?? []) + serverArgs
      return CatalogEntry(
        id: id
          ?? Catalog.makeId(family: family.name, modelLabel: model.label, build: self),
        family: family.name,
        size: model.label,
        releaseDate: model.releaseDate,
        ctxWindow: model.ctxWindow,
        fileSize: fileSize,
        ctxBytesPer1kTokens: ctxBytesPer1kTokens,
        overheadMultiplier: family.overheadMultiplier,
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
    let ctxWindow: Int
    let serverArgs: [String]?  // optional defaults for all builds
    let build: ModelBuild
    let quantizedBuilds: [ModelBuild]
  }

  struct ModelFamily {
    let name: String  // e.g. "Qwen3 2507"
    let series: String  // e.g. "qwen"
    let blurb: String  // short one- or two-sentence description
    let serverArgs: [String]?  // optional defaults for all models/builds
    let overheadMultiplier: Double  // overhead multiplier for file size
    let models: [Model]

    init(
      name: String,
      series: String,
      blurb: String,
      serverArgs: [String]? = nil,
      overheadMultiplier: Double = 1.05,
      models: [Model]
    ) {
      self.name = name
      self.series = series
      self.blurb = blurb
      self.serverArgs = serverArgs
      self.overheadMultiplier = overheadMultiplier
      self.models = models
    }

    var iconName: String {
      "ModelLogos/\(series.lowercased())"
    }
  }

  /// Families expressed with shared metadata to reduce duplication.
  /// Pre-sorted by name to eliminate runtime sorting overhead.
  static let families: [ModelFamily] = CatalogFamilies.families.sorted(by: { $0.name < $1.name })

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

  /// Cached catalog entries computed once at initialization.
  /// The catalog is defined statically and never changes at runtime, so we build this list once
  /// instead of rebuilding it on every menu open, download completion, or status check.
  /// Eliminates ~30+ struct allocations and nested iterations per refresh.
  private static let cachedEntries: [CatalogEntry] = {
    families.flatMap { family in
      family.models.flatMap { model -> [CatalogEntry] in
        let allBuilds = [model.build] + model.quantizedBuilds
        return allBuilds.map { build in build.asEntry(family: family, model: model) }
      }
    }
  }()

  /// Dictionary mapping model IDs to entries for O(1) lookups.
  /// Replaces linear search through families/models/builds when looking up by ID,
  /// which happens frequently during downloads and status checks.
  private static let entriesById: [String: CatalogEntry] = {
    Dictionary(uniqueKeysWithValues: cachedEntries.map { ($0.id, $0) })
  }()

  static func allEntries() -> [CatalogEntry] {
    cachedEntries
  }

  static func entry(forId id: String) -> CatalogEntry? {
    entriesById[id]
  }

  /// Gets system memory in Mb using shared system memory utility
  static var systemMemoryMb: UInt64 {
    return SystemMemory.memoryMb
  }

  /// Computes the usable context window (in tokens) that fits within the allowed memory budget.
  /// - Parameters:
  ///   - model: Catalog entry under evaluation.
  ///   - desiredTokens: Upper bound requested by the caller. When nil, defaults to the model's max.
  /// - Returns: Rounded context window (multiple of 1024) or nil when the model cannot satisfy the
  ///            minimum requirements.
  static func usableCtxWindow(
    for model: CatalogEntry,
    desiredTokens: Int? = nil
  ) -> Int? {
    let cacheKey = UsableContextCacheKey(modelId: model.id, desiredTokens: desiredTokens)
    if let cached = usableContextCache[cacheKey] {
      return cached
    }

    let minimumTokens = Int(minimumCtxWindowTokens)
    guard model.ctxWindow >= minimumTokens else { return nil }

    let systemMemoryMb = systemMemoryMb
    guard systemMemoryMb > 0 else { return nil }

    let memoryFraction = availableMemoryFraction(forSystemMemoryMb: systemMemoryMb)
    let availableMemoryMb = Double(systemMemoryMb) * memoryFraction
    let fileSizeMb = Double(model.fileSize) / 1_048_576.0
    let fileSizeWithOverheadMb = fileSizeMb * model.overheadMultiplier
    if fileSizeWithOverheadMb > availableMemoryMb { return nil }

    let effectiveDesired = desiredTokens.flatMap { $0 > 0 ? $0 : nil } ?? model.ctxWindow
    let desiredTokensDouble = Double(effectiveDesired)

    let ctxBytesPerToken = Double(model.ctxBytesPer1kTokens) / 1_000.0
    let maxTokensFromMemory: Double = {
      if ctxBytesPerToken <= 0 {
        return Double(model.ctxWindow)
      }
      let remainingMb = availableMemoryMb - fileSizeWithOverheadMb
      if remainingMb <= 0 { return 0 }
      let remainingBytes = remainingMb * 1_048_576.0
      return remainingBytes / ctxBytesPerToken
    }()

    let cappedTokens = min(Double(model.ctxWindow), desiredTokensDouble, maxTokensFromMemory)
    if cappedTokens < minimumCtxWindowTokens { return nil }

    let floored = Int(cappedTokens)
    var rounded = (floored / 1_024) * 1_024
    if rounded < minimumTokens { rounded = minimumTokens }
    if rounded > model.ctxWindow { rounded = model.ctxWindow }

    usableContextCache[cacheKey] = rounded

    return rounded
  }

  /// Computes compatibility info for a model and caches the result
  private static func compatibilityInfo(
    for model: CatalogEntry,
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> CompatibilityInfo {
    let cacheKey = CompatibilityCacheKey(modelId: model.id, tokens: ctxWindowTokens)
    if let cached = compatibilityCache[cacheKey] { return cached }

    func cache(_ info: CompatibilityInfo) -> CompatibilityInfo {
      compatibilityCache[cacheKey] = info
      return info
    }

    let minimumTokens = minimumCtxWindowTokens

    if Double(model.ctxWindow) < minimumTokens {
      return cache(
        CompatibilityInfo(
          isCompatible: false,
          incompatibilitySummary: "requires models with ≥4k context"
        ))
    }

    if ctxWindowTokens > 0 && ctxWindowTokens > Double(model.ctxWindow) {
      return cache(CompatibilityInfo(isCompatible: false, incompatibilitySummary: nil))
    }

    let systemMemoryMb = systemMemoryMb
    let memoryFraction = availableMemoryFraction(forSystemMemoryMb: systemMemoryMb)
    let estimatedMemoryUsageMb = runtimeMemoryUsageMb(
      for: model, ctxWindowTokens: ctxWindowTokens)

    func memoryRequirementSummary() -> String {
      let requiredTotalMb = UInt64(ceil(Double(estimatedMemoryUsageMb) / memoryFraction))
      let gb = ceil(Double(requiredTotalMb) / 1024.0)
      return String(format: "requires %.0f GB+ of memory", gb)
    }

    guard systemMemoryMb > 0 else {
      return cache(
        CompatibilityInfo(isCompatible: false, incompatibilitySummary: memoryRequirementSummary())
      )
    }

    let availableMemoryMb = Double(systemMemoryMb) * memoryFraction
    let isCompatible = estimatedMemoryUsageMb <= UInt64(availableMemoryMb)

    return cache(
      CompatibilityInfo(
        isCompatible: isCompatible,
        incompatibilitySummary: isCompatible ? nil : memoryRequirementSummary()
      ))
  }

  /// Checks if a model can fit within system memory constraints
  static func isModelCompatible(
    _ model: CatalogEntry,
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> Bool {
    compatibilityInfo(for: model, ctxWindowTokens: ctxWindowTokens).isCompatible
  }

  /// If incompatible, returns a short human-readable reason showing
  /// estimated memory needed (rounded to whole GB).
  /// Example: "needs ~12 GB of mem". Returns nil if compatible.
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
    let fileSizeMb = Double(model.fileSize) / 1_048_576.0
    let fileSizeWithOverheadMb = fileSizeMb * model.overheadMultiplier
    let ctxMultiplier = ctxWindowTokens / 1_000.0
    let ctxBytes = Double(model.ctxBytesPer1kTokens) * ctxMultiplier
    let ctxMb = ctxBytes / 1_048_576.0
    let totalMb = fileSizeWithOverheadMb + ctxMb
    return UInt64(ceil(totalMb))
  }

}

private typealias ModelFamily = Catalog.ModelFamily
private typealias Model = Catalog.Model
private typealias ModelBuild = Catalog.ModelBuild

enum CatalogFamilies {
  static let families: [Catalog.ModelFamily] = [
    // MARK: DeepSeek R1 0528 (migrated)
    ModelFamily(
      name: "DeepSeek R1 0528",
      series: "deepseek",
      blurb:
        "Reasoning‑forward DeepSeek R1 models distilled onto Qwen3 backbones; persuasive step‑by‑step behavior within local limits.",
      serverArgs: nil,
      models: [
        Model(
          label: "8B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 5, day: 29))!,
          ctxWindow: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "deepseek-r1-0528-qwen3-8b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 8_709_519_872,
            ctxBytesPer1kTokens: 150_994_944,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF/resolve/main/DeepSeek-R1-0528-Qwen3-8B-Q8_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "deepseek-r1-0528-qwen3-8b",
              quantization: "Q4_K_M",
              isFullPrecision: false,
              fileSize: 5_027_785_216,
              ctxBytesPer1kTokens: 150_994_944,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF/resolve/main/DeepSeek-R1-0528-Qwen3-8B-Q4_K_M.gguf"
              )!,
              additionalParts: nil,
              serverArgs: []
            )
          ]
        )
      ]
    ),
    // MARK: GPT-OSS (migrated)
    ModelFamily(
      name: "GPT-OSS",
      series: "gpt",
      blurb:
        "An open, GPT-style instruction-tuned family aimed at general-purpose assistance on local hardware.",
      // Sliding-window family: use max context by default
      serverArgs: ["-c", "0"],
      models: [
        Model(
          label: "20B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 2))!,
          ctxWindow: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gpt-oss-20b-mxfp4",
            quantization: "mxfp4",
            isFullPrecision: true,
            fileSize: 12_109_566_560,
            ctxBytesPer1kTokens: 25_165_824,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gpt-oss-20b-GGUF/resolve/main/gpt-oss-20b-mxfp4.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: []
        ),
        Model(
          label: "120B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 2))!,
          ctxWindow: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gpt-oss-120b-mxfp4",
            quantization: "mxfp4",
            isFullPrecision: true,
            fileSize: 63_387_346_464,
            ctxBytesPer1kTokens: 37_748_736,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gpt-oss-120b-GGUF/resolve/main/gpt-oss-120b-mxfp4-00001-of-00003.gguf"
            )!,
            additionalParts: [
              URL(
                string:
                  "https://huggingface.co/ggml-org/gpt-oss-120b-GGUF/resolve/main/gpt-oss-120b-mxfp4-00002-of-00003.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/ggml-org/gpt-oss-120b-GGUF/resolve/main/gpt-oss-120b-mxfp4-00003-of-00003.gguf"
              )!,
            ],
            serverArgs: []
          ),
          quantizedBuilds: []
        ),
      ]
    ),
    // MARK: Gemma 3 (QAT-trained) (migrated)
    ModelFamily(
      name: "Gemma 3",
      series: "gemma",
      blurb:
        "Gemma 3 models trained with quantization‑aware training (QAT) for better quality at low‑bit quantizations and smaller footprints.",
      serverArgs: nil,
      overheadMultiplier: 1.3,
      models: [
        Model(
          label: "27B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 24))!,
          ctxWindow: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3-qat-27b",
            quantization: "Q4_0",
            isFullPrecision: true,
            fileSize: 15_908_791_488,
            ctxBytesPer1kTokens: 83_886_080,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-27b-it-qat-GGUF/resolve/main/gemma-3-27b-it-qat-Q4_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: []
        ),
        Model(
          label: "12B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 21))!,
          ctxWindow: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3-qat-12b",
            quantization: "Q4_0",
            isFullPrecision: true,
            fileSize: 7_131_017_792,
            ctxBytesPer1kTokens: 67_108_864,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-12b-it-qat-GGUF/resolve/main/gemma-3-12b-it-qat-Q4_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: []
        ),
        Model(
          label: "4B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 22))!,
          ctxWindow: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3-qat-4b",
            quantization: "Q4_0",
            isFullPrecision: true,
            fileSize: 2_526_080_992,
            ctxBytesPer1kTokens: 20_971_520,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-4b-it-qat-GGUF/resolve/main/gemma-3-4b-it-qat-Q4_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: []
        ),
        Model(
          label: "1B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 27))!,
          ctxWindow: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3-qat-1b",
            quantization: "Q4_0",
            isFullPrecision: true,
            fileSize: 720_425_600,
            ctxBytesPer1kTokens: 4_194_304,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-1b-it-qat-GGUF/resolve/main/gemma-3-1b-it-qat-Q4_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: []
        ),
        Model(
          label: "270M",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 14))!,
          ctxWindow: 32_768,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3-qat-270m",
            quantization: "Q4_0",
            isFullPrecision: true,
            fileSize: 241_410_624,
            ctxBytesPer1kTokens: 3_145_728,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-270m-it-qat-GGUF/resolve/main/gemma-3-270m-it-qat-Q4_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: []
        ),
      ]
    ),
    // MARK: Gemma 3n (migrated)
    ModelFamily(
      name: "Gemma 3n",
      series: "gemma",
      blurb:
        "Google's efficient Gemma 3n line tuned for on‑device performance with solid instruction following at small scales.",
      // Sliding-window family: force max context and keep Gemma-specific overrides
      serverArgs: ["-c", "0", "-ot", "per_layer_token_embd.weight=CPU", "--no-mmap"],
      models: [
        Model(
          label: "E4B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 15))!,
          ctxWindow: 32_768,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3n-e4b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 7_353_292_256,
            ctxBytesPer1kTokens: 14_680_064,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3n-E4B-it-GGUF/resolve/main/gemma-3n-E4B-it-Q8_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "gemma-3n-e4b",
              quantization: "Q4_K_M",
              isFullPrecision: false,
              fileSize: 4_539_054_208,
              ctxBytesPer1kTokens: 14_680_064,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/gemma-3n-E4B-it-GGUF/resolve/main/gemma-3n-E4B-it-Q4_K_M.gguf"
              )!,
              additionalParts: nil,
              serverArgs: []
            )
          ]
        ),
        Model(
          label: "E2B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!,
          ctxWindow: 32_768,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3n-e2b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 4_788_112_064,
            ctxBytesPer1kTokens: 12_582_912,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q8_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "gemma-3n-e2b",
              quantization: "Q4_K_M",
              isFullPrecision: false,
              fileSize: 3_026_881_888,
              ctxBytesPer1kTokens: 12_582_912,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q4_K_M.gguf"
              )!,
              additionalParts: nil,
              serverArgs: []
            )
          ]
        ),
      ]
    ),
    // MARK: Qwen 3 Coder (migrated)
    ModelFamily(
      name: "Qwen 3 Coder",
      series: "qwen",
      blurb:
        "Qwen3 optimized for software tasks: strong code completion, instruction following, and long-context coding.",
      serverArgs: nil,
      overheadMultiplier: 1.1,
      models: [
        Model(
          label: "30B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 31))!,
          ctxWindow: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-coder-30b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 32_483_935_392,
            ctxBytesPer1kTokens: 100_663_296,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-coder-30b",
              quantization: "Q4_K_M",
              isFullPrecision: false,
              fileSize: 18_556_689_568,
              ctxBytesPer1kTokens: 100_663_296,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf"
              )!,
              additionalParts: nil,
              serverArgs: []
            )
          ]
        )
      ]
    ),
    // MARK: Qwen3 2507 (migrated to hierarchical form)
    ModelFamily(
      name: "Qwen 3 2507",
      series: "qwen",
      blurb:
        "Alibaba's latest Qwen3 refresh focused on instruction following, multilingual coverage, and long contexts across sizes.",
      serverArgs: nil,
      overheadMultiplier: 1.1,
      models: [
        Model(
          label: "30B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          ctxWindow: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-2507-30b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 32_483_932_576,
            ctxBytesPer1kTokens: 100_663_296,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Qwen3-30B-A3B-Instruct-2507-Q8_0-GGUF/resolve/main/qwen3-30b-a3b-instruct-2507-q8_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-2507-30b",
              quantization: "Q4_K_M",
              isFullPrecision: false,
              fileSize: 18_556_686_752,
              ctxBytesPer1kTokens: 100_663_296,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf"
              )!,
              additionalParts: nil,
              serverArgs: []
            )
          ]
        ),
        Model(
          label: "4B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          ctxWindow: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-2507-4b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 4_280_405_600,
            ctxBytesPer1kTokens: 150_994_944,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Qwen3-4B-Instruct-2507-Q8_0-GGUF/resolve/main/qwen3-4b-instruct-2507-q8_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-2507-4b",
              quantization: "Q4_K_M",
              isFullPrecision: false,
              fileSize: 2_497_281_120,
              ctxBytesPer1kTokens: 150_994_944,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
              )!,
              additionalParts: nil,
              serverArgs: []
            )
          ]
        ),
      ]
    ),
    // MARK: Qwen3 2507 Thinking (migrated)
    ModelFamily(
      name: "Qwen 3 2507 Thinking",
      series: "qwen",
      blurb:
        "Qwen3 models biased toward deliberate reasoning and step‑by‑step answers; useful for analysis and planning tasks.",
      serverArgs: nil,
      overheadMultiplier: 1.1,
      models: [
        Model(
          label: "30B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          ctxWindow: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-2507-thinking-30b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 32_483_932_576,
            ctxBytesPer1kTokens: 100_663_296,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Qwen3-30B-A3B-Thinking-2507-Q8_0-GGUF/resolve/main/qwen3-30b-a3b-thinking-2507-q8_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-2507-thinking-30b",
              quantization: "Q4_K_M",
              isFullPrecision: false,
              fileSize: 18_556_686_752,
              ctxBytesPer1kTokens: 100_663_296,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-30B-A3B-Thinking-2507-GGUF/resolve/main/Qwen3-30B-A3B-Thinking-2507-Q4_K_M.gguf"
              )!,
              additionalParts: nil,
              serverArgs: []
            )
          ]
        ),
        Model(
          label: "4B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          ctxWindow: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-2507-thinking-4b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 4_280_405_632,
            ctxBytesPer1kTokens: 150_994_944,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Qwen3-4B-Thinking-2507-Q8_0-GGUF/resolve/main/qwen3-4b-thinking-2507-q8_0.gguf"
            )!,
            additionalParts: nil,
            serverArgs: []
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-2507-thinking-4b",
              quantization: "Q4_K_M",
              isFullPrecision: false,
              fileSize: 2_497_281_152,
              ctxBytesPer1kTokens: 150_994_944,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-4B-Thinking-2507-GGUF/resolve/main/Qwen3-4B-Thinking-2507-Q4_K_M.gguf"
              )!,
              additionalParts: nil,
              serverArgs: []
            )
          ]
        ),
      ]
    ),
  ]
}
