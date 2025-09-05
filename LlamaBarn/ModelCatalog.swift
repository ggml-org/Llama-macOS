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
      
      contextLength: 131072,
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

    // 120B model, sharded mxfp4 quantization (3 parts)
    // llama-server should be pointed to the first shard; it will find the rest
    ModelCatalogEntry(
      id: "gpt-oss-120b-mxfp4",
      family: "GPT-OSS",
      variant: "120B",
      sizeInBillions: 120,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 2))!,
      
      contextLength: 131072,
      fileSizeMB: 63387,  // 63.39 GB across 3 shards
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
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/OpenAI",
      quantization: "mxfp4"
    ),

    // MARK: - DeepSeek R1 0528 Family
    // Latest reasoning models with enhanced efficiency

    // High quality 8B model with Q8_0 quantization
    ModelCatalogEntry(
      id: "deepseek-r1-0528-qwen3-8b-q8",
      family: "DeepSeek R1 0528",
      variant: "8B",
      sizeInBillions: 8,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 5, day: 29))!,
      
      contextLength: 131072,
      fileSizeMB: 8934,  // 8.71 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF/resolve/main/DeepSeek-R1-0528-Qwen3-8B-Q8_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/DeepSeek",
      quantization: "Q8_0"
    ),

    // 8B model with Q4_K_M quantization
    ModelCatalogEntry(
      id: "deepseek-r1-0528-qwen3-8b",
      family: "DeepSeek R1 0528",
      variant: "8B",
      sizeInBillions: 8,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 5, day: 29))!,
      
      contextLength: 131072,
      fileSizeMB: 5151,  // 5.03 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF/resolve/main/DeepSeek-R1-0528-Qwen3-8B-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/DeepSeek",
      quantization: "Q4_K_M"
    ),

    // MARK: - Qwen3 2507 Family
    // Latest generation 2507 models with enhanced performance and larger context

    // Largest model for most complex tasks - high quality variant
    ModelCatalogEntry(
      id: "qwen3-2507-235b-q8",
      family: "Qwen3 2507",
      variant: "235B",
      sizeInBillions: 235,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 256000,  // 250 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Qwen3-235B-A22B-Instruct-2507-Q8_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q8_0"
    ),

    // Largest model for most complex tasks
    ModelCatalogEntry(
      id: "qwen3-2507-235b",
      family: "Qwen3 2507",
      variant: "235B",
      sizeInBillions: 235,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 114688,  // 112 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Qwen3-235B-A22B-Instruct-2507-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q4_K_M"
    ),

    // Large model for complex reasoning tasks - high quality variant
    ModelCatalogEntry(
      id: "qwen3-2507-30b-q8",
      family: "Qwen3 2507",
      variant: "30B",
      sizeInBillions: 30,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 32768,  // 32 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q8_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q8_0"
    ),

    // Large model for complex reasoning tasks
    ModelCatalogEntry(
      id: "qwen3-2507-30b",
      family: "Qwen3 2507",
      variant: "30B",
      sizeInBillions: 30,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 15052,  // 14.7 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q4_K_M"
    ),

    // Mid-size model balancing performance and resource usage - high quality variant
    ModelCatalogEntry(
      id: "qwen3-2507-4b-q8",
      family: "Qwen3 2507",
      variant: "4B",
      sizeInBillions: 4,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 4384,  // 4.28 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q8_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q8_0"
    ),

    // Mid-size model balancing performance and resource usage
    ModelCatalogEntry(
      id: "qwen3-2507-4b",
      family: "Qwen3 2507",
      variant: "4B",
      sizeInBillions: 4,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 2560,  // 2.5 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q4_K_M"
    ),

    // MARK: - Qwen3 2507 Thinking Family
    // Reasoning models with step-by-step thinking capabilities

    // Largest thinking model - high quality variant
    ModelCatalogEntry(
      id: "qwen3-2507-thinking-235b-q8",
      family: "Qwen3 2507 Thinking",
      variant: "235B",
      sizeInBillions: 235,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 256000,  // 250 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Qwen3-235B-A22B-Thinking-2507-Q8_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q8_0"
    ),

    // Largest thinking model
    ModelCatalogEntry(
      id: "qwen3-2507-thinking-235b",
      family: "Qwen3 2507 Thinking",
      variant: "235B",
      sizeInBillions: 235,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 114688,  // 112 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Qwen3-235B-A22B-Thinking-2507-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q4_K_M"
    ),

    // Large thinking model - high quality variant
    ModelCatalogEntry(
      id: "qwen3-2507-thinking-30b-q8",
      family: "Qwen3 2507 Thinking",
      variant: "30B",
      sizeInBillions: 30,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 32768,  // 32 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-30B-A3B-Thinking-2507-GGUF/resolve/main/Qwen3-30B-A3B-Thinking-2507-Q8_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q8_0"
    ),

    // Large thinking model
    ModelCatalogEntry(
      id: "qwen3-2507-thinking-30b",
      family: "Qwen3 2507 Thinking",
      variant: "30B",
      sizeInBillions: 30,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 15052,  // 14.7 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-30B-A3B-Thinking-2507-GGUF/resolve/main/Qwen3-30B-A3B-Thinking-2507-Q4_K_M.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q4_K_M"
    ),

    // Compact thinking model - high quality variant
    ModelCatalogEntry(
      id: "qwen3-2507-thinking-4b-q8",
      family: "Qwen3 2507 Thinking",
      variant: "4B",
      sizeInBillions: 4,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 4384,  // 4.28 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-4B-Thinking-2507-GGUF/resolve/main/Qwen3-4B-Thinking-2507-Q8_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Qwen",
      quantization: "Q8_0"
    ),

    // Compact thinking model
    ModelCatalogEntry(
      id: "qwen3-2507-thinking-4b",
      family: "Qwen3 2507 Thinking",
      variant: "4B",
      sizeInBillions: 4,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
      
      contextLength: 262144,
      fileSizeMB: 2560,  // 2.5 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/unsloth/Qwen3-4B-Thinking-2507-GGUF/resolve/main/Qwen3-4B-Thinking-2507-Q4_K_M.gguf"
      )!,
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
      
      contextLength: 262144,
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
      
      contextLength: 262144,
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

    // MARK: - Gemma 3n Family
    // Multimodal models with vision and audio capabilities

    // Larger multimodal model with enhanced capabilities - high quality variant
    ModelCatalogEntry(
      id: "gemma-3n-e4b-q8",
      family: "Gemma 3n",
      variant: "E4B",
      sizeInBillions: 4,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 15))!,
      
      contextLength: 32768,
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
      
      contextLength: 32768,
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
      
      contextLength: 32768,
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

    // MARK: - Gemma 3 QAT Family
    // Quantization-aware trained models with enhanced efficiency and multimodal capabilities

    // Largest QAT model for most complex tasks
    ModelCatalogEntry(
      id: "gemma-3-qat-27b",
      family: "Gemma 3 QAT",
      variant: "27B",
      sizeInBillions: 27,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 24))!,
      
      contextLength: 131072,
      fileSizeMB: 15909,  // 15.9 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/ggml-org/gemma-3-27b-it-qat-GGUF/resolve/main/gemma-3-27b-it-qat-Q4_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Gemma",
      quantization: "Q4_0"
    ),

    // Large QAT model with enhanced efficiency
    ModelCatalogEntry(
      id: "gemma-3-qat-12b",
      family: "Gemma 3 QAT",
      variant: "12B",
      sizeInBillions: 12,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 21))!,
      
      contextLength: 131072,
      fileSizeMB: 7131,  // 6.98 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/ggml-org/gemma-3-12b-it-qat-GGUF/resolve/main/gemma-3-12b-it-qat-Q4_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Gemma",
      quantization: "Q4_0"
    ),

    // Compact QAT model balancing performance and efficiency
    ModelCatalogEntry(
      id: "gemma-3-qat-4b",
      family: "Gemma 3 QAT",
      variant: "4B",
      sizeInBillions: 4,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 22))!,
      
      contextLength: 131072,
      fileSizeMB: 2526,  // 2.53 GB
      downloadUrl: URL(
        string:
          "https://huggingface.co/ggml-org/gemma-3-4b-it-qat-GGUF/resolve/main/gemma-3-4b-it-qat-Q4_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Gemma",
      quantization: "Q4_0"
    ),

    // Compact QAT model for lightweight applications
    ModelCatalogEntry(
      id: "gemma-3-qat-1b",
      family: "Gemma 3 QAT",
      variant: "1B",
      sizeInBillions: 1,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 27))!,
      
      contextLength: 131072,
      fileSizeMB: 720,  // 720 MB
      downloadUrl: URL(
        string:
          "https://huggingface.co/ggml-org/gemma-3-1b-it-qat-GGUF/resolve/main/gemma-3-1b-it-qat-Q4_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Gemma",
      quantization: "Q4_0"
    ),

    // Ultra-compact QAT model for resource-constrained environments
    ModelCatalogEntry(
      id: "gemma-3-qat-270m",
      family: "Gemma 3 QAT",
      variant: "270M",
      sizeInBillions: 0.27,
      releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 14))!,
      
      contextLength: 32768,
      fileSizeMB: 241,  // 241 MB
      downloadUrl: URL(
        string:
          "https://huggingface.co/ggml-org/gemma-3-270m-it-qat-GGUF/resolve/main/gemma-3-270m-it-qat-Q4_0.gguf"
      )!,
      visionFile: nil,
      serverArgs: [],
      icon: "ModelLogos/Gemma",
      quantization: "Q4_0"
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
