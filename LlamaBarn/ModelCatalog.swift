import Foundation

/// Hugging Face api
/// - https://huggingface.co/api/models/{organization}/{model-name} -- model details
/// - https://huggingface.co/api/models?author={organization}&search={query} -- search based on author and query

/// Static catalog of available AI models with their configurations and metadata
enum ModelCatalog {

  /// Fraction of system memory available for models (75% - macOS reserves ~25%)
  static let availableMemoryFraction: Double = 0.75

  /// Multiplier to estimate runtime memory usage from model file size
  /// Models typically use ~25% more memory at runtime than their file size
  static let memoryUsageMultiplier: Double = 1.25

  // MARK: - New hierarchical catalog

  struct ModelBuild {
    let id: String?              // explicit ID for the leaf (preferred)
    let quantization: String
    let fileSizeMB: Int
    let downloadUrl: URL
    let additionalParts: [URL]?
    let serverArgs: [String]

    func asEntry(family: ModelFamily, variant: ModelVariant) -> ModelCatalogEntry {
      let effectiveArgs = (family.serverArgs ?? []) + (variant.serverArgs ?? []) + serverArgs
      return ModelCatalogEntry(
        id: id ?? ModelCatalog.makeId(family: family.name, variantLabel: variant.label, build: self),
        family: family.name,
        variant: variant.label,
        sizeInBillions: variant.sizeInBillions,
        releaseDate: variant.releaseDate,
        contextLength: variant.contextLength,
        fileSizeMB: fileSizeMB,
        downloadUrl: downloadUrl,
        additionalParts: additionalParts,
        serverArgs: effectiveArgs,
        icon: family.icon,
        quantization: quantization
      )
    }
  }

  struct ModelVariant {
    let label: String            // e.g. "4B", "30B"
    let sizeInBillions: Double
    let releaseDate: Date
    let contextLength: Int
    let serverArgs: [String]?    // optional defaults for all builds
    let builds: [ModelBuild]
  }

  struct ModelFamily {
    let name: String             // e.g. "Qwen3 2507"
    let icon: String             // asset name
    let blurb: String            // short one- or two-sentence description
    let license: String?         // optional license tidbit shown in UI
    let serverArgs: [String]?    // optional defaults for all variants/builds
    let variants: [ModelVariant]

    init(
      name: String,
      icon: String,
      blurb: String,
      license: String? = nil,
      serverArgs: [String]? = nil,
      variants: [ModelVariant]
    ) {
      self.name = name
      self.icon = icon
      self.blurb = blurb
      self.license = license
      self.serverArgs = serverArgs
      self.variants = variants
    }
  }

  /// Families expressed with shared metadata to reduce duplication
  private static let families: [ModelFamily] = [
    // MARK: Qwen3 2507 (migrated to hierarchical form)
    ModelFamily(
      name: "Qwen3 2507",
      icon: "ModelLogos/Qwen",
      blurb: "Alibaba's latest Qwen3 refresh focused on instruction following, multilingual coverage, and long contexts across sizes.",
      license: "Qwen License",
      serverArgs: nil,
      variants: [
        ModelVariant(
          label: "235B",
          sizeInBillions: 235,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          contextLength: 262_144,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "qwen3-2507-235b-q8",
              quantization: "Q8_0",
              fileSizeMB: 256_000,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Qwen3-235B-A22B-Instruct-2507-Q8_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
            ModelBuild(
              id: "qwen3-2507-235b",
              quantization: "Q4_K_M",
              fileSizeMB: 114_688,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Qwen3-235B-A22B-Instruct-2507-Q4_K_M.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
        ModelVariant(
          label: "30B",
          sizeInBillions: 30,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          contextLength: 262_144,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "qwen3-2507-30b-q8",
              quantization: "Q8_0",
              fileSizeMB: 32_768,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q8_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
            ModelBuild(
              id: "qwen3-2507-30b",
              quantization: "Q4_K_M",
              fileSizeMB: 15_052,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
        ModelVariant(
          label: "4B",
          sizeInBillions: 4,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          contextLength: 262_144,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "qwen3-2507-4b-q8",
              quantization: "Q8_0",
              fileSizeMB: 4_384,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q8_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
            ModelBuild(
              id: "qwen3-2507-4b",
              quantization: "Q4_K_M",
              fileSizeMB: 2_560,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
      ]
    ),
    // MARK: GPT-OSS (migrated)
    ModelFamily(
      name: "GPT-OSS",
      icon: "ModelLogos/OpenAI",
      blurb: "An open, GPT-style instruction-tuned family aimed at general-purpose assistance on local hardware.",
      license: "Open license",
      serverArgs: nil,
      variants: [
        ModelVariant(
          label: "20B",
          sizeInBillions: 20,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 2))!,
          contextLength: 131_072,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "gpt-oss-20b-mxfp4",
              quantization: "mxfp4",
              fileSizeMB: 12_390,
              downloadUrl: URL(string: "https://huggingface.co/ggml-org/gpt-oss-20b-GGUF/resolve/main/gpt-oss-20b-mxfp4.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
        ModelVariant(
          label: "120B",
          sizeInBillions: 120,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 2))!,
          contextLength: 131_072,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "gpt-oss-120b-mxfp4",
              quantization: "mxfp4",
              fileSizeMB: 63_387,
              downloadUrl: URL(string: "https://huggingface.co/ggml-org/gpt-oss-120b-GGUF/resolve/main/gpt-oss-120b-mxfp4-00001-of-00003.gguf")!,
              additionalParts: [
                URL(string: "https://huggingface.co/ggml-org/gpt-oss-120b-GGUF/resolve/main/gpt-oss-120b-mxfp4-00002-of-00003.gguf")!,
                URL(string: "https://huggingface.co/ggml-org/gpt-oss-120b-GGUF/resolve/main/gpt-oss-120b-mxfp4-00003-of-00003.gguf")!,
              ],
              serverArgs: []
            ),
          ]
        ),
      ]
    ),
    // MARK: Qwen 3 Coder (migrated)
    ModelFamily(
      name: "Qwen 3 Coder",
      icon: "ModelLogos/Qwen",
      blurb: "Qwen3 optimized for software tasks: strong code completion, instruction following, and long-context coding.",
      license: "Qwen License",
      serverArgs: nil,
      variants: [
        ModelVariant(
          label: "30B",
          sizeInBillions: 30,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 31))!,
          contextLength: 262_144,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "qwen3-coder-30b-q8",
              quantization: "Q8_0",
              fileSizeMB: 33_280,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
            ModelBuild(
              id: "qwen3-coder-30b",
              quantization: "Q4_K_M",
              fileSizeMB: 19_046,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
      ]
    ),
    // MARK: Gemma 3n (migrated)
    ModelFamily(
      name: "Gemma 3n",
      icon: "ModelLogos/Gemma",
      blurb: "Google's efficient Gemma 3n line tuned for on‑device performance with solid instruction following at small scales.",
      license: "Gemma License",
      serverArgs: ["-ot", "per_layer_token_embd.weight=CPU", "--no-mmap"],
      variants: [
        ModelVariant(
          label: "E4B",
          sizeInBillions: 4,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 15))!,
          contextLength: 32_768,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "gemma-3n-e4b-q8",
              quantization: "Q8_0",
              fileSizeMB: 7_526,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/gemma-3n-E4B-it-GGUF/resolve/main/gemma-3n-E4B-it-Q8_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
            ModelBuild(
              id: "gemma-3n-e4b",
              quantization: "Q4_K_M",
              fileSizeMB: 4_505,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/gemma-3n-E4B-it-GGUF/resolve/main/gemma-3n-E4B-it-Q4_K_M.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
        ModelVariant(
          label: "E2B",
          sizeInBillions: 1,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!,
          contextLength: 32_768,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "gemma-3n-e2b",
              quantization: "Q4_K_M",
              fileSizeMB: 3_103,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q4_K_M.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
      ]
    ),
    // MARK: Gemma 3 QAT (migrated)
    ModelFamily(
      name: "Gemma 3 QAT",
      icon: "ModelLogos/Gemma",
      blurb: "Gemma 3 models trained with quantization awareness for better quality at low‑bit quantizations and smaller footprints.",
      license: "Gemma License",
      serverArgs: nil,
      variants: [
        ModelVariant(
          label: "27B",
          sizeInBillions: 27,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 24))!,
          contextLength: 131_072,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "gemma-3-qat-27b",
              quantization: "Q4_0",
              fileSizeMB: 15_909,
              downloadUrl: URL(string: "https://huggingface.co/ggml-org/gemma-3-27b-it-qat-GGUF/resolve/main/gemma-3-27b-it-qat-Q4_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
        ModelVariant(
          label: "12B",
          sizeInBillions: 12,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 21))!,
          contextLength: 131_072,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "gemma-3-qat-12b",
              quantization: "Q4_0",
              fileSizeMB: 7_131,
              downloadUrl: URL(string: "https://huggingface.co/ggml-org/gemma-3-12b-it-qat-GGUF/resolve/main/gemma-3-12b-it-qat-Q4_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
        ModelVariant(
          label: "4B",
          sizeInBillions: 4,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 22))!,
          contextLength: 131_072,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "gemma-3-qat-4b",
              quantization: "Q4_0",
              fileSizeMB: 2_526,
              downloadUrl: URL(string: "https://huggingface.co/ggml-org/gemma-3-4b-it-qat-GGUF/resolve/main/gemma-3-4b-it-qat-Q4_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
        ModelVariant(
          label: "1B",
          sizeInBillions: 1,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 27))!,
          contextLength: 131_072,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "gemma-3-qat-1b",
              quantization: "Q4_0",
              fileSizeMB: 720,
              downloadUrl: URL(string: "https://huggingface.co/ggml-org/gemma-3-1b-it-qat-GGUF/resolve/main/gemma-3-1b-it-qat-Q4_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
        ModelVariant(
          label: "270M",
          sizeInBillions: 0.27,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 14))!,
          contextLength: 32_768,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "gemma-3-qat-270m",
              quantization: "Q4_0",
              fileSizeMB: 241,
              downloadUrl: URL(string: "https://huggingface.co/ggml-org/gemma-3-270m-it-qat-GGUF/resolve/main/gemma-3-270m-it-qat-Q4_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
      ]
    ),
    // MARK: Qwen3 2507 Thinking (migrated)
    ModelFamily(
      name: "Qwen3 2507 Thinking",
      icon: "ModelLogos/Qwen",
      blurb: "Qwen3 variants biased toward deliberate reasoning and step‑by‑step answers; useful for analysis and planning tasks.",
      license: "Qwen License",
      serverArgs: nil,
      variants: [
        ModelVariant(
          label: "235B",
          sizeInBillions: 235,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          contextLength: 262_144,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "qwen3-2507-thinking-235b-q8",
              quantization: "Q8_0",
              fileSizeMB: 256_000,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Qwen3-235B-A22B-Thinking-2507-Q8_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
            ModelBuild(
              id: "qwen3-2507-thinking-235b",
              quantization: "Q4_K_M",
              fileSizeMB: 114_688,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Qwen3-235B-A22B-Thinking-2507-Q4_K_M.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
        ModelVariant(
          label: "30B",
          sizeInBillions: 30,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          contextLength: 262_144,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "qwen3-2507-thinking-30b-q8",
              quantization: "Q8_0",
              fileSizeMB: 32_768,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-30B-A3B-Thinking-2507-GGUF/resolve/main/Qwen3-30B-A3B-Thinking-2507-Q8_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
            ModelBuild(
              id: "qwen3-2507-thinking-30b",
              quantization: "Q4_K_M",
              fileSizeMB: 15_052,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-30B-A3B-Thinking-2507-GGUF/resolve/main/Qwen3-30B-A3B-Thinking-2507-Q4_K_M.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
        ModelVariant(
          label: "4B",
          sizeInBillions: 4,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          contextLength: 262_144,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "qwen3-2507-thinking-4b-q8",
              quantization: "Q8_0",
              fileSizeMB: 4_384,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Thinking-2507-GGUF/resolve/main/Qwen3-4B-Thinking-2507-Q8_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
            ModelBuild(
              id: "qwen3-2507-thinking-4b",
              quantization: "Q4_K_M",
              fileSizeMB: 2_560,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Thinking-2507-GGUF/resolve/main/Qwen3-4B-Thinking-2507-Q4_K_M.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
      ]
    ),
    // MARK: DeepSeek R1 0528 (migrated)
    ModelFamily(
      name: "DeepSeek R1 0528",
      icon: "ModelLogos/DeepSeek",
      blurb: "Reasoning‑forward DeepSeek R1 variants distilled onto Qwen3 backbones; persuasive step‑by‑step behavior within local limits.",
      license: "DeepSeek License",
      serverArgs: nil,
      variants: [
        ModelVariant(
          label: "8B",
          sizeInBillions: 8,
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 5, day: 29))!,
          contextLength: 131_072,
          serverArgs: nil,
          builds: [
            ModelBuild(
              id: "deepseek-r1-0528-qwen3-8b-q8",
              quantization: "Q8_0",
              fileSizeMB: 8_934,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF/resolve/main/DeepSeek-R1-0528-Qwen3-8B-Q8_0.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
            ModelBuild(
              id: "deepseek-r1-0528-qwen3-8b",
              quantization: "Q4_K_M",
              fileSizeMB: 5_151,
              downloadUrl: URL(string: "https://huggingface.co/unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF/resolve/main/DeepSeek-R1-0528-Qwen3-8B-Q4_K_M.gguf")!,
              additionalParts: nil,
              serverArgs: []
            ),
          ]
        ),
      ]
    ),
  ]

  // MARK: - ID + flatten helpers

  private static func slug(_ s: String) -> String {
    return s
      .lowercased()
      .replacingOccurrences(of: " ", with: "-")
      .replacingOccurrences(of: "/", with: "-")
  }

  /// Preserves existing ID scheme when an explicit build.id is not provided:
  /// - Q8_0 builds use suffix "-q8"
  /// - mxfp4 builds use suffix "-mxfp4"
  /// - other builds omit suffix
  private static func makeId(family: String, variantLabel: String, build: ModelBuild) -> String {
    let familySlug = slug(family)
    let variantSlug = slug(variantLabel)
    var base = "\(familySlug)-\(variantSlug)"
    // DeepSeek R1 legacy IDs included "-qwen3" segment
    if familySlug == "deepseek-r1-0528" {
      base = "\(familySlug)-qwen3-\(variantSlug)"
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
  static var uiFamilies: [ModelFamily] { families }

  static func allEntries() -> [ModelCatalogEntry] {
    families.flatMap { family in
      family.variants.flatMap { variant in
        variant.builds.map { build in build.asEntry(family: family, variant: variant) }
      }
    }
  }

  static func entry(forId id: String) -> ModelCatalogEntry? {
    for family in families {
      for variant in family.variants {
        for build in variant.builds {
          let entry = build.asEntry(family: family, variant: variant)
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

  /// Checks if a model can fit within system memory constraints
  static func isModelCompatible(_ model: ModelCatalogEntry) -> Bool {
    let systemMemoryMB = getSystemMemoryMB()
    let availableMemoryMB = UInt64(Double(systemMemoryMB) * availableMemoryFraction)
    let estimatedMemoryUsageMB = UInt64(Double(model.fileSizeMB) * memoryUsageMultiplier)
    return estimatedMemoryUsageMB <= availableMemoryMB
  }

  /// Returns all model families, showing the best model from each family regardless of memory constraints
  /// If no models in a family fit in memory, shows the smallest model from that family
  static func allFamiliesForSystem() -> [ModelCatalogEntry] {
    guard getSystemMemoryMB() > 0 else { return [] }

    // Group models by family and select representative model for each
    let modelsByFamily = Dictionary(grouping: allEntries(), by: { $0.family })

    return modelsByFamily.compactMap { (_, familyModels) in
      selectRepresentativeModel(from: familyModels)
    }
    .sorted { lhs, rhs in lhs.family < rhs.family }
  }

  /// Selects the best representative model from a family
  /// Returns largest compatible model, or smallest model if none are compatible
  private static func selectRepresentativeModel(from familyModels: [ModelCatalogEntry])
    -> ModelCatalogEntry?
  {
    let compatibleModels = familyModels.filter(isModelCompatible)

    if !compatibleModels.isEmpty {
      // Return largest compatible model
      return compatibleModels.max(by: compareModelsBySize)
    } else {
      // Return smallest model from family
      return familyModels.min(by: compareModelsBySize)
    }
  }

  /// Compares models by size (file size first, then parameters as tiebreaker)
  private static func compareModelsBySize(_ lhs: ModelCatalogEntry, _ rhs: ModelCatalogEntry)
    -> Bool
  {
    if lhs.fileSizeMB != rhs.fileSizeMB {
      return lhs.fileSizeMB < rhs.fileSizeMB
    }
    return lhs.sizeInBillions < rhs.sizeInBillions
  }
}
