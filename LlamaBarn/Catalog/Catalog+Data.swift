import Foundation

extension Catalog {
  /// Helper to create dates concisely for model release dates
  private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
  }

  // MARK: - Model Catalog Data

  /// Families expressed with shared metadata to reduce duplication.
  static let families: [ModelFamily] = [
    // MARK: GPT-OSS
    ModelFamily(
      name: "GPT-OSS",
      series: "gpt",
      description:
        "OpenAI's first open-weight models since GPT-2. Built for reasoning, agentic tasks, and developer use with function calling and tool use capabilities.",
      serverArgs: ["--temp", "1.0", "--top-p", "1.0"],
      sizes: [
        ModelSize(
          name: "20B",
          parameterCount: 20_000_000_000,
          releaseDate: date(2025, 8, 2),
          ctxWindow: 131_072,
          ctxBytesPer1kTokens: 25_165_824,
          build: ModelBuild(
            id: "gpt-oss-20b-mxfp4",
            quantization: "mxfp4",
            fileSize: 12_109_566_560,
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
          ctxBytesPer1kTokens: 37_748_736,
          build: ModelBuild(
            id: "gpt-oss-120b-mxfp4",
            quantization: "mxfp4",
            fileSize: 63_387_346_464,
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
      description:
        "Google's multimodal models built from Gemini technology. Supports 140+ languages, vision, and text tasks with up to 128K context for edge to cloud deployment.",
      serverArgs: nil,
      overheadMultiplier: 1.3,
      sizes: [
        ModelSize(
          name: "27B",
          parameterCount: 27_432_406_640,
          releaseDate: date(2025, 4, 24),
          ctxWindow: 131_072,
          ctxBytesPer1kTokens: 83_886_080,
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/gemma-3-27b-it-qat-GGUF/resolve/main/mmproj-model-f16-27B.gguf"
          )!,
          build: ModelBuild(
            id: "gemma-3-qat-27b",
            quantization: "Q4_0",
            fileSize: 15_908_791_488,
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
          ctxBytesPer1kTokens: 67_108_864,
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/gemma-3-12b-it-qat-GGUF/resolve/main/mmproj-model-f16-12B.gguf"
          )!,
          build: ModelBuild(
            id: "gemma-3-qat-12b",
            quantization: "Q4_0",
            fileSize: 7_131_017_792,
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
          ctxBytesPer1kTokens: 20_971_520,
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/gemma-3-4b-it-qat-GGUF/resolve/main/mmproj-model-f16-4B.gguf"
          )!,
          build: ModelBuild(
            id: "gemma-3-qat-4b",
            quantization: "Q4_0",
            fileSize: 2_526_080_992,
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
          ctxWindow: 32_768,
          ctxBytesPer1kTokens: 4_194_304,
          build: ModelBuild(
            id: "gemma-3-qat-1b",
            quantization: "Q4_0",
            fileSize: 720_425_600,
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
          ctxBytesPer1kTokens: 3_145_728,
          build: ModelBuild(
            id: "gemma-3-qat-270m",
            quantization: "Q4_0",
            fileSize: 241_410_624,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/gemma-3-270m-it-qat-GGUF/resolve/main/gemma-3-270m-it-qat-Q4_0.gguf"
            )!
          )
        ),
      ]
    ),
    // MARK: Qwen3
    ModelFamily(
      name: "Qwen3",
      series: "qwen",
      description:
        "Alibaba's hybrid reasoning models with thinking/non-thinking modes. Excels at coding, math, and multilingual tasks across 119 languages.",
      serverArgs: ["--temp", "0.6", "--top-k", "20", "--top-p", "0.95", "--min-p", "0"],
      overheadMultiplier: 1.1,
      sizes: [
        ModelSize(
          name: "4B",
          parameterCount: 4_022_468_096,
          releaseDate: date(2025, 7, 1),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 150_994_944,
          build: ModelBuild(
            id: "qwen3-2507-4b-q8",
            quantization: "Q8_0",
            fileSize: 4_280_405_600,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "4B Thinking",
          parameterCount: 4_022_468_096,
          releaseDate: date(2025, 7, 1),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 150_994_944,
          build: ModelBuild(
            id: "qwen3-2507-thinking-4b-q8",
            quantization: "Q8_0",
            fileSize: 4_280_405_632,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-4B-Thinking-2507-GGUF/resolve/main/Qwen3-4B-Thinking-2507-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "30B-A3B",
          parameterCount: 30_532_122_624,
          releaseDate: date(2025, 7, 1),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 100_663_296,
          build: ModelBuild(
            id: "qwen3-2507-30b-q8",
            quantization: "Q8_0",
            fileSize: 32_483_932_576,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "30B-A3B Thinking",
          parameterCount: 30_532_122_624,
          releaseDate: date(2025, 7, 1),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 100_663_296,
          build: ModelBuild(
            id: "qwen3-2507-thinking-30b-q8",
            quantization: "Q8_0",
            fileSize: 32_483_932_576,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-30B-A3B-Thinking-2507-GGUF/resolve/main/Qwen3-30B-A3B-Thinking-2507-Q4_K_M.gguf"
              )!
            )
          ]
        ),
      ]
    ),
    // MARK: Qwen3-VL
    ModelFamily(
      name: "Qwen3 VL",
      series: "qwen",
      description:
        "Alibaba's vision-language model for understanding text, images, and video. Features OCR in 32 languages, GUI agents, and spatial reasoning.",
      serverArgs: ["--temp", "0.7", "--top-p", "0.8", "--top-k", "20"],
      overheadMultiplier: 1.1,
      sizes: [
        ModelSize(
          name: "2B",
          parameterCount: 2_127_532_032,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 117_440_512,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-instruct-2b-q8",
            quantization: "Q8_0",
            fileSize: 1_834_427_424,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/main/Qwen3VL-2B-Instruct-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "2B Thinking",
          parameterCount: 2_127_532_032,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 117_440_512,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-2B-Thinking-GGUF/resolve/main/mmproj-Qwen3VL-2B-Thinking-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-thinking-2b-q8",
            quantization: "Q8_0",
            fileSize: 1_834_427_360,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-2B-Thinking-GGUF/resolve/main/Qwen3VL-2B-Thinking-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "4B",
          parameterCount: 4_437_815_808,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 150_994_944,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-4B-Instruct-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-instruct-4b-q8",
            quantization: "Q8_0",
            fileSize: 4_280_406_144,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/resolve/main/Qwen3VL-4B-Instruct-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "4B Thinking",
          parameterCount: 4_437_815_808,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 150_994_944,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-4B-Thinking-GGUF/resolve/main/mmproj-Qwen3VL-4B-Thinking-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-thinking-4b-q8",
            quantization: "Q8_0",
            fileSize: 4_280_405_952,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-4B-Thinking-GGUF/resolve/main/Qwen3VL-4B-Thinking-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "8B",
          parameterCount: 8_767_123_696,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 150_994_944,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-instruct-8b-q8",
            quantization: "Q8_0",
            fileSize: 8_709_519_456,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "8B Thinking",
          parameterCount: 8_767_123_696,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 150_994_944,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-8B-Thinking-GGUF/resolve/main/mmproj-Qwen3VL-8B-Thinking-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-thinking-8b-q8",
            quantization: "Q8_0",
            fileSize: 8_709_519_360,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-8B-Thinking-GGUF/resolve/main/Qwen3VL-8B-Thinking-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "30B-A3B",
          parameterCount: 31_070_754_032,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 100_663_296,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-30B-A3B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-30B-A3B-Instruct-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-instruct-30b-q8",
            quantization: "Q8_0",
            fileSize: 32_483_932_992,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-30B-A3B-Instruct-GGUF/resolve/main/Qwen3VL-30B-A3B-Instruct-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "30B-A3B Thinking",
          parameterCount: 31_070_754_032,
          releaseDate: date(2025, 10, 31),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 100_663_296,
          mmproj: URL(
            string:
              "https://huggingface.co/Qwen/Qwen3-VL-30B-A3B-Thinking-GGUF/resolve/main/mmproj-Qwen3VL-30B-A3B-Thinking-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "qwen3-vl-thinking-30b-q8",
            quantization: "Q8_0",
            fileSize: 32_483_933_024,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/Qwen/Qwen3-VL-30B-A3B-Thinking-GGUF/resolve/main/Qwen3VL-30B-A3B-Thinking-Q4_K_M.gguf"
              )!
            )
          ]
        ),
      ]
    ),
    // MARK: Qwen3-Coder
    ModelFamily(
      name: "Qwen3 Coder",
      series: "qwen",
      description:
        "Alibaba's specialized coding model for agentic software engineering. Optimized for function calling, tool use, and repository-scale reasoning.",
      serverArgs: ["--temp", "0.7", "--top-p", "0.8", "--top-k", "20"],
      overheadMultiplier: 1.1,
      sizes: [
        ModelSize(
          name: "30B-A3B",
          parameterCount: 30_532_122_624,
          releaseDate: date(2025, 7, 31),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 100_663_296,
          build: ModelBuild(
            id: "qwen3-coder-30b-q8",
            quantization: "Q8_0",
            fileSize: 32_483_935_392,
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
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf"
              )!
            )
          ]
        )
      ]
    ),
    // MARK: Nemotron Nano 3
    ModelFamily(
      name: "Nemotron Nano 3",
      series: "nvidia",
      description:
        "NVIDIA's efficient hybrid MoE model for agentic AI. Built for reasoning, coding, and tool use with 1M token context and 4x faster throughput.",
      serverArgs: nil,
      sizes: [
        ModelSize(
          name: "30B-A3B",
          parameterCount: 31_577_940_288,
          releaseDate: date(2025, 12, 15),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 6_291_456,
          build: ModelBuild(
            id: "nemotron-nano-3-30b-q8",
            quantization: "Q8_0",
            fileSize: 33_585_495_328,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Nemotron-Nano-3-30B-A3B-GGUF/resolve/main/Nemotron-Nano-3-30B-A3B-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "nemotron-nano-3-30b",
              quantization: "Q4_K_M",
              fileSize: 24_515_129_632,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/ggml-org/Nemotron-Nano-3-30B-A3B-GGUF/resolve/main/Nemotron-Nano-3-30B-A3B-Q4_K_M.gguf"
              )!
            )
          ]
        )
      ]
    ),
    // MARK: Ministral 3
    ModelFamily(
      name: "Ministral 3",
      series: "mistral",
      description:
        "Mistral AI's compact edge models with vision capabilities. Offers best cost-to-performance ratio for on-device deployment in 3B, 8B, 14B sizes.",
      serverArgs: nil,
      sizes: [
        ModelSize(
          name: "3B",
          parameterCount: 4_000_000_000,
          releaseDate: date(2025, 12, 2),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 106_496_000,
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/Ministral-3-3B-Instruct-2512-GGUF/resolve/main/mmproj-Ministral-3-3B-Instruct-2512-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "ministral-3-instruct-3b-q8",
            quantization: "Q8_0",
            fileSize: 3_913_606_144,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-3B-Instruct-2512-GGUF/resolve/main/Ministral-3-3B-Instruct-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "ministral-3-instruct-3b",
              quantization: "Q4_K_M",
              fileSize: 2_147_023_008,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512-GGUF/resolve/main/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "3B Reasoning",
          parameterCount: 4_000_000_000,
          releaseDate: date(2025, 12, 2),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 106_496_000,
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/Ministral-3-3B-Reasoning-2512-GGUF/resolve/main/mmproj-Ministral-3-3B-Reasoning-2512-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "ministral-3-reasoning-3b-q8",
            quantization: "Q8_0",
            fileSize: 3_916_269_568,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-3B-Reasoning-2512-GGUF/resolve/main/Ministral-3-3B-Reasoning-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "ministral-3-reasoning-3b",
              quantization: "Q4_K_M",
              fileSize: 2_147_021_472,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/mistralai/Ministral-3-3B-Reasoning-2512-GGUF/resolve/main/Ministral-3-3B-Reasoning-2512-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "8B",
          parameterCount: 9_000_000_000,
          releaseDate: date(2025, 12, 2),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 139_264_000,
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/Ministral-3-8B-Instruct-2512-GGUF/resolve/main/mmproj-Ministral-3-8B-Instruct-2512-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "ministral-3-instruct-8b-q8",
            quantization: "Q8_0",
            fileSize: 9_703_104_512,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-8B-Instruct-2512-GGUF/resolve/main/Ministral-3-8B-Instruct-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "ministral-3-instruct-8b",
              quantization: "Q4_K_M",
              fileSize: 5_198_911_904,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/mistralai/Ministral-3-8B-Instruct-2512-GGUF/resolve/main/Ministral-3-8B-Instruct-2512-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "8B Reasoning",
          parameterCount: 9_000_000_000,
          releaseDate: date(2025, 12, 2),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 139_264_000,
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/Ministral-3-8B-Reasoning-2512-GGUF/resolve/main/mmproj-Ministral-3-8B-Reasoning-2512-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "ministral-3-reasoning-8b-q8",
            quantization: "Q8_0",
            fileSize: 9_701_376_000,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-8B-Reasoning-2512-GGUF/resolve/main/Ministral-3-8B-Reasoning-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "ministral-3-reasoning-8b",
              quantization: "Q4_K_M",
              fileSize: 5_198_910_368,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/mistralai/Ministral-3-8B-Reasoning-2512-GGUF/resolve/main/Ministral-3-8B-Reasoning-2512-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "14B",
          parameterCount: 14_000_000_000,
          releaseDate: date(2025, 12, 2),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 163_840_000,
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/Ministral-3-14B-Instruct-2512-GGUF/resolve/main/mmproj-Ministral-3-14B-Instruct-2512-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "ministral-3-instruct-14b-q8",
            quantization: "Q8_0",
            fileSize: 14_359_311_264,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-14B-Instruct-2512-GGUF/resolve/main/Ministral-3-14B-Instruct-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "ministral-3-instruct-14b",
              quantization: "Q4_K_M",
              fileSize: 8_239_593_024,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/mistralai/Ministral-3-14B-Instruct-2512-GGUF/resolve/main/Ministral-3-14B-Instruct-2512-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "14B Reasoning",
          parameterCount: 14_000_000_000,
          releaseDate: date(2025, 12, 2),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 163_840_000,
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/Ministral-3-14B-Reasoning-2512-GGUF/resolve/main/mmproj-Ministral-3-14B-Reasoning-2512-Q8_0.gguf"
          )!,
          build: ModelBuild(
            id: "ministral-3-reasoning-14b-q8",
            quantization: "Q8_0",
            fileSize: 14_359_309_728,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-14B-Reasoning-2512-GGUF/resolve/main/Ministral-3-14B-Reasoning-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "ministral-3-reasoning-14b",
              quantization: "Q4_K_M",
              fileSize: 8_239_591_488,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/mistralai/Ministral-3-14B-Reasoning-2512-GGUF/resolve/main/Ministral-3-14B-Reasoning-2512-Q4_K_M.gguf"
              )!
            )
          ]
        ),
      ]
    ),
    // MARK: Devstral 2
    ModelFamily(
      name: "Devstral 2",
      series: "mistral",
      description:
        "Mistral AI's agentic coding models for software engineering tasks. Excels at exploring codebases, multi-file editing, and powering code agents.",
      serverArgs: nil,
      sizes: [
        ModelSize(
          name: "24B",
          parameterCount: 24_000_000_000,
          releaseDate: date(2025, 12, 18),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 167_772_160,
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/Devstral-Small-2-24B-Instruct-2512-GGUF/resolve/main/mmproj-Devstral-Small-2-24B-Instruct-2512-F16.gguf"
          )!,
          build: ModelBuild(
            id: "devstral-small-2-24b-q8",
            quantization: "Q8_0",
            fileSize: 25_055_308_352,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Devstral-Small-2-24B-Instruct-2512-GGUF/resolve/main/Devstral-Small-2-24B-Instruct-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "devstral-small-2-24b-q4km",
              quantization: "Q4_K_M",
              fileSize: 14_334_446_752,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF/resolve/main/Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "123B",
          parameterCount: 123_000_000_000,
          releaseDate: date(2025, 12, 19),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 369_098_752,
          build: ModelBuild(
            id: "devstral-2-123b-q8",
            quantization: "Q8_0",
            fileSize: 132_854_938_656,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Devstral-2-123B-Instruct-2512-GGUF/resolve/main/Devstral-2-123B-Instruct-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "devstral-2-123b-q4km",
              quantization: "Q4_K_M",
              fileSize: 74_897_662_400,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Devstral-2-123B-Instruct-2512-GGUF/resolve/main/Q4_K_M/Devstral-2-123B-Instruct-2512-Q4_K_M-00001-of-00002.gguf"
              )!,
              additionalParts: [
                URL(
                  string:
                    "https://huggingface.co/unsloth/Devstral-2-123B-Instruct-2512-GGUF/resolve/main/Q4_K_M/Devstral-2-123B-Instruct-2512-Q4_K_M-00002-of-00002.gguf"
                )!
              ]
            )
          ]
        ),
      ]
    ),
  ]
}
