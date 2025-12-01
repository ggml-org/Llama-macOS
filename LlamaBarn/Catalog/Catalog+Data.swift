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
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/gemma-3-27b-it-qat-GGUF/resolve/main/mmproj-model-f16-27B.gguf"
          )!,
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
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/gemma-3-12b-it-qat-GGUF/resolve/main/mmproj-model-f16-12B.gguf"
          )!,
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
          mmproj: URL(
            string:
              "https://huggingface.co/ggml-org/gemma-3-4b-it-qat-GGUF/resolve/main/mmproj-model-f16-4B.gguf"
          )!,
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
      name: "Qwen3 Coder",
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
      name: "Qwen3 VL",
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
      name: "Qwen3 VL Thinking",
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
