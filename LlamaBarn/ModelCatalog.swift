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

  /// All models available for download and use in LlamaBarn
  static let models: [ModelCatalogEntry] = [

    // MARK: - GPT-OSS Family
    // Open-source GPT model with enhanced capabilities

    // 20B model with mxfp4 quantization
    ModelCatalogEntry(
      id: "gpt-oss-20b-mxfp4",
      family: "GPT-OSS",
      variant: "20B",
      sizeInBillions: 20,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 2))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 12390,  // 12.1 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/ggml-org/gpt-oss-20b-GGUF/resolve/main/gpt-oss-20b-mxfp4.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/OpenAI",
      quantization: "mxfp4"
    ),

    // MARK: - DeepSeek R1 Distill Family
    // Distilled reasoning models with enhanced efficiency

    // High quality 70B model with Q4_K_M quantization
    ModelCatalogEntry(
      id: "deepseek-r1-distill-llama-70b",
      family: "DeepSeek R1 Distill",
      variant: "70B",
      sizeInBillions: 70,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 20))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 43520,  // 42.5 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Llama-70B-GGUF/resolve/main/DeepSeek-R1-Distill-Llama-70B-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/DeepSeek",
      quantization: "Q4_K_M"
    ),

    // High quality 32B model with Q8_0 quantization
    ModelCatalogEntry(
      id: "deepseek-r1-distill-qwen-32b-q8",
      family: "DeepSeek R1 Distill",
      variant: "32B",
      sizeInBillions: 32,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 20))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 34800,  // 34.8 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-32B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-32B-Q8_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/DeepSeek",
      quantization: "Q8_0"
    ),

    // 32B model with Q4_K_M quantization
    ModelCatalogEntry(
      id: "deepseek-r1-distill-qwen-32b",
      family: "DeepSeek R1 Distill",
      variant: "32B",
      sizeInBillions: 32,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 20))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 19900,  // 19.9 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-32B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/DeepSeek",
      quantization: "Q4_K_M"
    ),

    // 14B model with Q4_K_M quantization
    ModelCatalogEntry(
      id: "deepseek-r1-distill-qwen-14b",
      family: "DeepSeek R1 Distill",
      variant: "14B",
      sizeInBillions: 14,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 20))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 9216,  // 8.99 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-14B-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/DeepSeek",
      quantization: "Q4_K_M"
    ),

    // 8B model with Q4_K_M quantization
    ModelCatalogEntry(
      id: "deepseek-r1-distill-llama-8b",
      family: "DeepSeek R1 Distill",
      variant: "8B",
      sizeInBillions: 8,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 20))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 4920,  // 4.92 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Llama-8B-GGUF/resolve/main/DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/DeepSeek",
      quantization: "Q4_K_M"
    ),

    // Compact 1.5B model with Q4_K_M quantization
    ModelCatalogEntry(
      id: "deepseek-r1-distill-qwen-1.5b",
      family: "DeepSeek R1 Distill",
      variant: "1.5B",
      sizeInBillions: 1.5,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 20))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 1120,  // 1.12 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/DeepSeek",
      quantization: "Q4_K_M"
    ),

    // MARK: - Qwen 3 Family
    // Latest generation models with strong tool support

    // Largest model for most complex tasks - high quality variant
    ModelCatalogEntry(
      id: "qwen3-32b-q8",
      family: "Qwen 3",
      variant: "32B",
      sizeInBillions: 32,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 29))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 35635,  // 34.8 GB
      downloadUrl: URL(
        string: "https://huggingface.co/unsloth/Qwen3-32B-GGUF/resolve/main/Qwen3-32B-Q8_0.gguf")!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q8_0"
    ),

    // Largest model for most complex tasks
    ModelCatalogEntry(
      id: "qwen3-32b",
      family: "Qwen 3",
      variant: "32B",
      sizeInBillions: 32,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 29))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 20275,  // 19.8 GB
      downloadUrl: URL(
        string: "https://huggingface.co/unsloth/Qwen3-32B-GGUF/resolve/main/Qwen3-32B-Q4_K_M.gguf")!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q4_K_M"
    ),

    // Large model for complex reasoning tasks
    ModelCatalogEntry(
      id: "qwen3-14b",
      family: "Qwen 3",
      variant: "14B",
      sizeInBillions: 14,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 29))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 9216,  // 9 GB
      downloadUrl: URL(
        string: "https://huggingface.co/unsloth/Qwen3-14B-GGUF/resolve/main/Qwen3-14B-Q4_K_M.gguf")!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q4_K_M"
    ),

    // Large model for complex tasks requiring high reasoning capability
    ModelCatalogEntry(
      id: "qwen3-8b",
      family: "Qwen 3",
      variant: "8B",
      sizeInBillions: 8,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 29))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 5150,  // 5.03 GB
      downloadUrl: URL(
        string: "https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf")!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q4_K_M"
    ),

    // Mid-size model balancing performance and resource usage
    ModelCatalogEntry(
      id: "qwen3-4b",
      family: "Qwen 3",
      variant: "4B",
      sizeInBillions: 4,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 29))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 2560,  // 2.5 GB
      downloadUrl: URL(
        string: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf")!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q4_K_M"
    ),

    // MARK: - Qwen 3 Coder Family
    // Specialized coding models with enhanced programming capabilities

    // Large specialized coding model - high quality variant
    ModelCatalogEntry(
      id: "qwen3-coder-30b-q8",
      family: "Qwen 3 Coder",
      variant: "30B",
      sizeInBillions: 30,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 31))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 33280,  // 32.5 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q8_0"
    ),

    // Large specialized coding model
    ModelCatalogEntry(
      id: "qwen3-coder-30b",
      family: "Qwen 3 Coder",
      variant: "30B",
      sizeInBillions: 30,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 31))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 19046,  // 18.6 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q4_K_M"
    ),

    // MARK: - Llama 3.3 Family
    // Latest large instruct model with enhanced capabilities

    // Large model for complex reasoning and instruction following
    ModelCatalogEntry(
      id: "llama-3.3-70b-instruct",
      family: "Llama 3.3",
      variant: "70B",
      sizeInBillions: 70,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 12, day: 6))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 43520,  // 42.5 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Llama-3.3-70B-Instruct-GGUF/resolve/main/Llama-3.3-70B-Instruct-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Meta",
      quantization: "Q4_K_M"
    ),

    // MARK: - Llama 3.2 Family
    // Compact instruct model optimized for efficiency

    // Compact model with Q4_K_M quantization for efficient performance
    ModelCatalogEntry(
      id: "llama-3.2-3b-instruct",
      family: "Llama 3.2",
      variant: "3B",
      sizeInBillions: 3,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 9, day: 25))!,
      supportsVision: false,
      supportsAudio: false,
      supportsTools: true,
      fileSizeMB: 2068,  // 2.02 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Meta",
      quantization: "Q4_K_M"
    ),

    // MARK: - Gemma 3n Family
    // Multimodal models with vision and audio capabilities

    // Larger multimodal model with enhanced capabilities - high quality variant
    ModelCatalogEntry(
      id: "gemma-3n-e4b-q8",
      family: "Gemma 3n",
      variant: "E4B",
      sizeInBillions: 4,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 15))!,
      supportsVision: true,
      supportsAudio: true,
      supportsTools: false,
      fileSizeMB: 7526,  // 7.35 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/gemma-3n-E4B-it-GGUF/resolve/main/gemma-3n-E4B-it-Q8_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: ["-ot", "per_layer_token_embd.weight=CPU", "--no-mmap"],
      icon: "ModelLogos/Gemma",
      quantization: "Q8_0"
    ),

    // Larger multimodal model with enhanced capabilities
    ModelCatalogEntry(
      id: "gemma-3n-e4b",
      family: "Gemma 3n",
      variant: "E4B",
      sizeInBillions: 4,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 15))!,
      supportsVision: true,
      supportsAudio: true,
      supportsTools: false,
      fileSizeMB: 4505,  // 4.4 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/gemma-3n-E4B-it-GGUF/resolve/main/gemma-3n-E4B-it-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: ["-ot", "per_layer_token_embd.weight=CPU", "--no-mmap"],
      icon: "ModelLogos/Gemma",
      quantization: "Q4_K_M"
    ),

    // Compact multimodal model with vision and audio support
    // Note: Requires special server args for proper memory management
    ModelCatalogEntry(
      id: "gemma-3n-e2b",
      family: "Gemma 3n",
      variant: "E2B",
      sizeInBillions: 1,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!,
      supportsVision: true,
      supportsAudio: true,
      supportsTools: false,
      fileSizeMB: 3103,  // 3.03 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: ["-ot", "per_layer_token_embd.weight=CPU", "--no-mmap"],  // Memory optimization flags
      icon: "ModelLogos/Gemma",
      quantization: "Q4_K_M"
    ),
  ]

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
    let modelsByFamily = Dictionary(grouping: models, by: { $0.family })

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
