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
      self.sizes = sizes
    }

    var iconName: String {
      "ModelLogos/\(series.lowercased())"
    }
  }

  struct ModelSize {
    let name: String  // e.g. "4B", "30B"
    let parameterCount: Int64  // Total model parameters
    let releaseDate: Date
    let ctxWindow: Int
    let serverArgs: [String]?  // optional defaults for all builds
    let mmproj: URL?  // optional vision projection file for multimodal models
    let build: ModelBuild
    let quantizedBuilds: [ModelBuild]

    init(
      name: String,
      parameterCount: Int64,
      releaseDate: Date,
      ctxWindow: Int,
      serverArgs: [String]? = nil,
      mmproj: URL? = nil,
      build: ModelBuild,
      quantizedBuilds: [ModelBuild] = []
    ) {
      self.name = name
      self.parameterCount = parameterCount
      self.releaseDate = releaseDate
      self.ctxWindow = ctxWindow
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
    /// Estimated KV-cache bytes needed for a 1k-token context.
    let ctxBytesPer1kTokens: Int
    let downloadUrl: URL
    let additionalParts: [URL]?
    let serverArgs: [String]?

    init(
      id: String,
      quantization: String,
      fileSize: Int64,
      ctxBytesPer1kTokens: Int,
      downloadUrl: URL,
      additionalParts: [URL]? = nil,
      serverArgs: [String]? = nil
    ) {
      self.id = id
      self.quantization = quantization
      self.fileSize = fileSize
      self.ctxBytesPer1kTokens = ctxBytesPer1kTokens
      self.downloadUrl = downloadUrl
      self.additionalParts = additionalParts
      self.serverArgs = serverArgs
    }
  }

  // MARK: - Public Data

  /// Pre-sorted by name to avoid runtime sorting.
  static let families: [ModelFamily] = familiesUnsorted.sorted(by: { $0.name < $1.name })

  // MARK: - Public Accessors

  /// Returns all catalog entries by traversing the hierarchy
  static func allModels() -> [CatalogEntry] {
    families.flatMap { family in
      family.sizes.flatMap { size in
        ([size.build] + size.quantizedBuilds).map { build in
          entry(family: family, size: size, build: build)
        }
      }
    }
  }

  /// Map of filename -> CatalogEntry for O(1) lookup.
  /// Used to efficiently identify installed models from files on disk.
  static let modelsByFilename: [String: CatalogEntry] = {
    var map = [String: CatalogEntry]()
    for model in allModels() {
      map[model.downloadUrl.lastPathComponent] = model
    }
    return map
  }()

  /// Finds a catalog entry by ID by traversing the hierarchy
  static func findModel(id: String) -> CatalogEntry? {
    for family in families {
      for size in family.sizes {
        for build in [size.build] + size.quantizedBuilds {
          if build.id == id {
            return entry(family: family, size: size, build: build)
          }
        }
      }
    }
    return nil
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
    desiredTokens: Int? = nil
  ) -> Int? {
    let minimumTokens = Int(minimumCtxWindowTokens)
    guard model.ctxWindow >= minimumTokens else { return nil }

    let sysMem = SystemMemory.memoryMb
    guard sysMem > 0 else { return nil }

    let budgetMb = memoryBudget(systemMemoryMb: sysMem)
    let fileSizeWithOverheadMb = fileSizeWithOverhead(for: model)
    if fileSizeWithOverheadMb > budgetMb { return nil }

    let effectiveDesired = desiredTokens.flatMap { $0 > 0 ? $0 : nil } ?? model.ctxWindow
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
    var rounded = (floored / 1_024) * 1_024
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
  private static func entry(family: ModelFamily, size: ModelSize, build: ModelBuild)
    -> CatalogEntry
  {
    let effectiveArgs =
      (family.serverArgs ?? []) + (size.serverArgs ?? []) + (build.serverArgs ?? [])

    // Merge size's mmproj (if present) with build's additionalParts (for multi-part splits)
    let effectiveParts: [URL]? = {
      var parts: [URL] = []
      if let mmproj = size.mmproj {
        parts.append(mmproj)
      }
      if let buildParts = build.additionalParts {
        parts.append(contentsOf: buildParts)
      }
      return parts.isEmpty ? nil : parts
    }()

    let isFullPrecision = build.id == size.build.id

    return CatalogEntry(
      id: build.id,
      family: family.name,
      parameterCount: size.parameterCount,
      size: size.name,
      releaseDate: size.releaseDate,
      ctxWindow: size.ctxWindow,
      fileSize: build.fileSize,
      ctxBytesPer1kTokens: build.ctxBytesPer1kTokens,
      overheadMultiplier: family.overheadMultiplier,
      downloadUrl: build.downloadUrl,
      additionalParts: effectiveParts,
      serverArgs: effectiveArgs,
      icon: family.iconName,
      quantization: build.quantization,
      isFullPrecision: isFullPrecision
    )
  }

  /// Helper to create dates concisely for model release dates
  private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
  }

  // MARK: - Model Catalog Data

  /// Families expressed with shared metadata to reduce duplication.
  private static let familiesUnsorted: [ModelFamily] = [
    // MARK: GPT-OSS
    ModelFamily(
      name: "GPT-OSS",
      series: "gpt",
      // Sliding-window family: use max context by default
      serverArgs: ["-c", "0", "--temp", "1.0", "--top-p", "1.0"],
      sizes: [
        ModelSize(
          name: "20B",
          parameterCount: 20_000_000_000,
          releaseDate: date(2025, 8, 2),
          ctxWindow: 131_072,
          build: ModelBuild(
            id: "gpt-oss-20b-mxfp4",
            quantization: "mxfp4",
            fileSize: 12_109_566_560,
            ctxBytesPer1kTokens: 25_165_824,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gpt-oss-20b-GGUF/resolve/main/gpt-oss-20b-mxfp4.gguf"
            )!
          )
        ),
        ModelSize(
          name: "120B",
          parameterCount: 120_000_000_000,
          releaseDate: date(2025, 8, 2),
          ctxWindow: 131_072,
          build: ModelBuild(
            id: "gpt-oss-120b-mxfp4",
            quantization: "mxfp4",
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
            ]
          )
        ),
      ]
    ),
    // MARK: Gemma 3
    ModelFamily(
      name: "Gemma 3",
      series: "gemma",
      serverArgs: nil,
      overheadMultiplier: 1.3,
      sizes: [
        ModelSize(
          name: "27B",
          parameterCount: 27_432_406_640,
          releaseDate: date(2025, 4, 24),
          ctxWindow: 131_072,
          build: ModelBuild(
            id: "gemma-3-qat-27b",
            quantization: "Q4_0",
            fileSize: 15_908_791_488,
            ctxBytesPer1kTokens: 83_886_080,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-27b-it-qat-GGUF/resolve/main/gemma-3-27b-it-qat-Q4_0.gguf"
            )!
          )
        ),
        ModelSize(
          name: "12B",
          parameterCount: 12_187_325_040,
          releaseDate: date(2025, 4, 21),
          ctxWindow: 131_072,
          build: ModelBuild(
            id: "gemma-3-qat-12b",
            quantization: "Q4_0",
            fileSize: 7_131_017_792,
            ctxBytesPer1kTokens: 67_108_864,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-12b-it-qat-GGUF/resolve/main/gemma-3-12b-it-qat-Q4_0.gguf"
            )!
          )
        ),
        ModelSize(
          name: "4B",
          parameterCount: 4_300_079_472,
          releaseDate: date(2025, 4, 22),
          ctxWindow: 131_072,
          build: ModelBuild(
            id: "gemma-3-qat-4b",
            quantization: "Q4_0",
            fileSize: 2_526_080_992,
            ctxBytesPer1kTokens: 20_971_520,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-4b-it-qat-GGUF/resolve/main/gemma-3-4b-it-qat-Q4_0.gguf"
            )!
          )
        ),
        ModelSize(
          name: "1B",
          parameterCount: 999_885_952,
          releaseDate: date(2025, 8, 27),
          ctxWindow: 131_072,
          build: ModelBuild(
            id: "gemma-3-qat-1b",
            quantization: "Q4_0",
            fileSize: 720_425_600,
            ctxBytesPer1kTokens: 4_194_304,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-1b-it-qat-GGUF/resolve/main/gemma-3-1b-it-qat-Q4_0.gguf"
            )!
          )
        ),
        ModelSize(
          name: "270M",
          parameterCount: 268_098_176,
          releaseDate: date(2025, 8, 14),
          ctxWindow: 32_768,
          build: ModelBuild(
            id: "gemma-3-qat-270m",
            quantization: "Q4_0",
            fileSize: 241_410_624,
            ctxBytesPer1kTokens: 3_145_728,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-270m-it-qat-GGUF/resolve/main/gemma-3-270m-it-qat-Q4_0.gguf"
            )!
          )
        ),
      ]
    ),
    // MARK: Gemma 3n
    ModelFamily(
      name: "Gemma 3n",
      series: "gemma",
      // Sliding-window family: force max context and keep Gemma-specific overrides
      serverArgs: ["-c", "0", "-ot", "per_layer_token_embd.weight=CPU", "--no-mmap"],
      sizes: [
        ModelSize(
          name: "E4B",
          parameterCount: 7_849_978_192,
          releaseDate: date(2024, 1, 15),
          ctxWindow: 32_768,
          build: ModelBuild(
            id: "gemma-3n-e4b-q8",
            quantization: "Q8_0",
            fileSize: 7_353_292_256,
            ctxBytesPer1kTokens: 14_680_064,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3n-E4B-it-GGUF/resolve/main/gemma-3n-E4B-it-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "gemma-3n-e4b",
              quantization: "Q4_K_M",
              fileSize: 4_539_054_208,
              ctxBytesPer1kTokens: 14_680_064,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/gemma-3n-E4B-it-GGUF/resolve/main/gemma-3n-E4B-it-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "E2B",
          parameterCount: 5_439_438_272,
          releaseDate: date(2024, 1, 1),
          ctxWindow: 32_768,
          build: ModelBuild(
            id: "gemma-3n-e2b-q8",
            quantization: "Q8_0",
            fileSize: 4_788_112_064,
            ctxBytesPer1kTokens: 12_582_912,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "gemma-3n-e2b",
              quantization: "Q4_K_M",
              fileSize: 3_026_881_888,
              ctxBytesPer1kTokens: 12_582_912,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q4_K_M.gguf"
              )!
            )
          ]
        ),
      ]
    ),
    // MARK: Qwen3-Coder
    ModelFamily(
      name: "Qwen3-Coder",
      series: "qwen",
      serverArgs: ["--temp", "0.7", "--top-p", "0.8", "--top-k", "20"],
      overheadMultiplier: 1.1,
      sizes: [
        ModelSize(
          name: "30B-A3B",
          parameterCount: 30_532_122_624,
          releaseDate: date(2025, 7, 31),
          ctxWindow: 262_144,
          build: ModelBuild(
            id: "qwen3-coder-30b-q8",
            quantization: "Q8_0",
            fileSize: 32_483_935_392,
            ctxBytesPer1kTokens: 100_663_296,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-coder-30b",
              quantization: "Q4_K_M",
              fileSize: 18_556_689_568,
              ctxBytesPer1kTokens: 100_663_296,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf"
              )!
            )
          ]
        )
      ]
    ),
    // MARK: Qwen3 2507
    ModelFamily(
      name: "Qwen3 2507",
      series: "qwen",
      serverArgs: ["--temp", "0.6", "--top-k", "20", "--top-p", "0.95", "--min-p", "0"],
      overheadMultiplier: 1.1,
      sizes: [
        ModelSize(
          name: "30B-A3B",
          parameterCount: 30_532_122_624,
          releaseDate: date(2025, 7, 1),
          ctxWindow: 262_144,
          build: ModelBuild(
            id: "qwen3-2507-30b-q8",
            quantization: "Q8_0",
            fileSize: 32_483_932_576,
            ctxBytesPer1kTokens: 100_663_296,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Qwen3-30B-A3B-Instruct-2507-Q8_0-GGUF/resolve/main/qwen3-30b-a3b-instruct-2507-q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-2507-30b",
              quantization: "Q4_K_M",
              fileSize: 18_556_686_752,
              ctxBytesPer1kTokens: 100_663_296,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "4B",
          parameterCount: 4_022_468_096,
          releaseDate: date(2025, 7, 1),
          ctxWindow: 262_144,
          build: ModelBuild(
            id: "qwen3-2507-4b-q8",
            quantization: "Q8_0",
            fileSize: 4_280_405_600,
            ctxBytesPer1kTokens: 150_994_944,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Qwen3-4B-Instruct-2507-Q8_0-GGUF/resolve/main/qwen3-4b-instruct-2507-q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-2507-4b",
              quantization: "Q4_K_M",
              fileSize: 2_497_281_120,
              ctxBytesPer1kTokens: 150_994_944,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
              )!
            )
          ]
        ),
      ]
    ),
    // MARK: Qwen3 2507 Thinking
    ModelFamily(
      name: "Qwen3 2507 Thinking",
      series: "qwen",
      serverArgs: ["--temp", "0.6", "--top-k", "20", "--top-p", "0.95", "--min-p", "0"],
      overheadMultiplier: 1.1,
      sizes: [
        ModelSize(
          name: "30B-A3B",
          parameterCount: 30_532_122_624,
          releaseDate: date(2025, 7, 1),
          ctxWindow: 262_144,
          build: ModelBuild(
            id: "qwen3-2507-thinking-30b-q8",
            quantization: "Q8_0",
            fileSize: 32_483_932_576,
            ctxBytesPer1kTokens: 100_663_296,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Qwen3-30B-A3B-Thinking-2507-Q8_0-GGUF/resolve/main/qwen3-30b-a3b-thinking-2507-q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-2507-thinking-30b",
              quantization: "Q4_K_M",
              fileSize: 18_556_686_752,
              ctxBytesPer1kTokens: 100_663_296,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-30B-A3B-Thinking-2507-GGUF/resolve/main/Qwen3-30B-A3B-Thinking-2507-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "4B",
          parameterCount: 4_022_468_096,
          releaseDate: date(2025, 7, 1),
          ctxWindow: 262_144,
          build: ModelBuild(
            id: "qwen3-2507-thinking-4b-q8",
            quantization: "Q8_0",
            fileSize: 4_280_405_632,
            ctxBytesPer1kTokens: 150_994_944,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Qwen3-4B-Thinking-2507-Q8_0-GGUF/resolve/main/qwen3-4b-thinking-2507-q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-2507-thinking-4b",
              quantization: "Q4_K_M",
              fileSize: 2_497_281_152,
              ctxBytesPer1kTokens: 150_994_944,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-4B-Thinking-2507-GGUF/resolve/main/Qwen3-4B-Thinking-2507-Q4_K_M.gguf"
              )!
            )
          ]
        ),
      ]
    ),
    // MARK: Qwen3-VL
    ModelFamily(
      name: "Qwen3-VL",
      series: "qwen",
      serverArgs: ["--temp", "0.7", "--top-p", "0.8", "--top-k", "20"],
      overheadMultiplier: 1.1,
      sizes: [
        ModelSize(
          name: "30B-A3B",
          parameterCount: 31_070_754_032,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-30B-A3B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-30B-A3B-Instruct-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-instruct-30b-q8",
            quantization: "Q8_0",
            fileSize: 32_483_932_992,
            ctxBytesPer1kTokens: 100_663_296,
            downloadUrl: URL(
              string:
                "https://huggingface.co/Qwen/Qwen3-VL-30B-A3B-Instruct-GGUF/resolve/main/Qwen3VL-30B-A3B-Instruct-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-vl-instruct-30b",
              quantization: "Q4_K_M",
              fileSize: 18_556_687_168,
              ctxBytesPer1kTokens: 100_663_296,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-30B-A3B-Instruct-GGUF/resolve/main/Qwen3VL-30B-A3B-Instruct-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "8B",
          parameterCount: 8_767_123_696,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-instruct-8b-q8",
            quantization: "Q8_0",
            fileSize: 8_709_519_456,
            ctxBytesPer1kTokens: 150_994_944,
            downloadUrl: URL(
              string:
                "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/Qwen3VL-8B-Instruct-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-vl-instruct-8b",
              quantization: "Q4_K_M",
              fileSize: 5_027_784_800,
              ctxBytesPer1kTokens: 150_994_944,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "4B",
          parameterCount: 4_437_815_808,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-4B-Instruct-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-instruct-4b-q8",
            quantization: "Q8_0",
            fileSize: 4_280_406_144,
            ctxBytesPer1kTokens: 150_994_944,
            downloadUrl: URL(
              string:
                "https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/resolve/main/Qwen3VL-4B-Instruct-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-vl-instruct-4b",
              quantization: "Q4_K_M",
              fileSize: 2_497_281_664,
              ctxBytesPer1kTokens: 150_994_944,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/resolve/main/Qwen3VL-4B-Instruct-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "2B",
          parameterCount: 2_127_532_032,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-instruct-2b-q8",
            quantization: "Q8_0",
            fileSize: 1_834_427_424,
            ctxBytesPer1kTokens: 117_440_512,
            downloadUrl: URL(
              string:
                "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/main/Qwen3VL-2B-Instruct-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-vl-instruct-2b",
              quantization: "Q4_K_M",
              fileSize: 1_107_409_952,
              ctxBytesPer1kTokens: 117_440_512,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/main/Qwen3VL-2B-Instruct-Q4_K_M.gguf"
              )!
            )
          ]
        ),
      ]
    ),
    // MARK: Qwen3-VL Thinking
    ModelFamily(
      name: "Qwen3-VL Thinking",
      series: "qwen",
      serverArgs: ["--temp", "0.6", "--top-p", "0.95", "--top-k", "20"],
      overheadMultiplier: 1.1,
      sizes: [
        ModelSize(
          name: "30B-A3B",
          parameterCount: 31_070_754_032,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-30B-A3B-Thinking-GGUF/resolve/main/mmproj-Qwen3VL-30B-A3B-Thinking-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-thinking-30b-q8",
            quantization: "Q8_0",
            fileSize: 32_483_933_024,
            ctxBytesPer1kTokens: 100_663_296,
            downloadUrl: URL(
              string:
                "https://huggingface.co/Qwen/Qwen3-VL-30B-A3B-Thinking-GGUF/resolve/main/Qwen3VL-30B-A3B-Thinking-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-vl-thinking-30b",
              quantization: "Q4_K_M",
              fileSize: 18_556_687_200,
              ctxBytesPer1kTokens: 100_663_296,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-30B-A3B-Thinking-GGUF/resolve/main/Qwen3VL-30B-A3B-Thinking-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "8B",
          parameterCount: 8_767_123_696,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-8B-Thinking-GGUF/resolve/main/mmproj-Qwen3VL-8B-Thinking-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-thinking-8b-q8",
            quantization: "Q8_0",
            fileSize: 8_709_519_360,
            ctxBytesPer1kTokens: 150_994_944,
            downloadUrl: URL(
              string:
                "https://huggingface.co/Qwen/Qwen3-VL-8B-Thinking-GGUF/resolve/main/Qwen3VL-8B-Thinking-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-vl-thinking-8b",
              quantization: "Q4_K_M",
              fileSize: 5_027_784_704,
              ctxBytesPer1kTokens: 150_994_944,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-8B-Thinking-GGUF/resolve/main/Qwen3VL-8B-Thinking-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "4B",
          parameterCount: 4_437_815_808,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-4B-Thinking-GGUF/resolve/main/mmproj-Qwen3VL-4B-Thinking-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-thinking-4b-q8",
            quantization: "Q8_0",
            fileSize: 4_280_405_952,
            ctxBytesPer1kTokens: 150_994_944,
            downloadUrl: URL(
              string:
                "https://huggingface.co/Qwen/Qwen3-VL-4B-Thinking-GGUF/resolve/main/Qwen3VL-4B-Thinking-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-vl-thinking-4b",
              quantization: "Q4_K_M",
              fileSize: 2_497_281_472,
              ctxBytesPer1kTokens: 150_994_944,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-4B-Thinking-GGUF/resolve/main/Qwen3VL-4B-Thinking-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "2B",
          parameterCount: 2_127_532_032,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-2B-Thinking-GGUF/resolve/main/mmproj-Qwen3VL-2B-Thinking-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-thinking-2b-q8",
            quantization: "Q8_0",
            fileSize: 1_834_427_360,
            ctxBytesPer1kTokens: 117_440_512,
            downloadUrl: URL(
              string:
                "https://huggingface.co/Qwen/Qwen3-VL-2B-Thinking-GGUF/resolve/main/Qwen3VL-2B-Thinking-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-vl-thinking-2b",
              quantization: "Q4_K_M",
              fileSize: 1_107_409_888,
              ctxBytesPer1kTokens: 117_440_512,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-2B-Thinking-GGUF/resolve/main/Qwen3VL-2B-Thinking-Q4_K_M.gguf"
              )!
            )
          ]
        ),
      ]
    ),
  ]

}
