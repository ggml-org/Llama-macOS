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
    // MARK: Qwen 3.5 Small
    ModelFamily(
      name: "Qwen 3.5 Small",
      series: "qwen",
      description:
        "Alibaba's compact natively multimodal reasoning models. Supports thinking/non-thinking modes for text and vision tasks across 201 languages.",
      serverArgs: ["--temp", "0.6", "--top-k", "20", "--top-p", "0.95", "--min-p", "0"],
      overheadMultiplier: 1.1,
      sizes: [
        ModelSize(
          name: "0.8B",
          parameterCount: 758_372_368,
          releaseDate: date(2026, 3, 3),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 12_582_912,
          mmproj: URL(
            string:
              "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/mmproj-F16.gguf"
          )!,
          mmprojLocalFilename: "Qwen3.5-0.8B-mmproj-F16.gguf",
          build: ModelBuild(
            quantization: "Q8_0",
            fileSize: 811_843_840,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              quantization: "UD-Q4_K_XL",
              fileSize: 558_772_480,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-UD-Q4_K_XL.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "2B",
          parameterCount: 1_887_854_608,
          releaseDate: date(2026, 3, 3),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 12_582_912,
          mmproj: URL(
            string:
              "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/mmproj-F16.gguf"
          )!,
          mmprojLocalFilename: "Qwen3.5-2B-mmproj-F16.gguf",
          build: ModelBuild(
            quantization: "Q8_0",
            fileSize: 2_012_012_800,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              quantization: "UD-Q4_K_XL",
              fileSize: 1_339_752_704,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-UD-Q4_K_XL.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "4B",
          parameterCount: 4_212_196_816,
          releaseDate: date(2026, 3, 3),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 33_554_432,
          mmproj: URL(
            string:
              "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/mmproj-F16.gguf"
          )!,
          mmprojLocalFilename: "Qwen3.5-4B-mmproj-F16.gguf",
          build: ModelBuild(
            quantization: "Q8_0",
            fileSize: 4_482_403_488,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              quantization: "UD-Q4_K_XL",
              fileSize: 2_912_109_728,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-UD-Q4_K_XL.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "9B",
          parameterCount: 8_960_348_656,
          releaseDate: date(2026, 3, 3),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 33_554_432,
          mmproj: URL(
            string:
              "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/mmproj-F16.gguf"
          )!,
          mmprojLocalFilename: "Qwen3.5-9B-mmproj-F16.gguf",
          build: ModelBuild(
            quantization: "Q8_0",
            fileSize: 9_527_502_048,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              quantization: "UD-Q4_K_XL",
              fileSize: 5_966_095_584,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-UD-Q4_K_XL.gguf"
              )!
            )
          ]
        ),
      ]
    ),
    // MARK: Qwen 3.5 Medium
    ModelFamily(
      name: "Qwen 3.5 Medium",
      series: "qwen",
      description:
        "Alibaba's flagship natively multimodal reasoning models. Dense and MoE variants that rival models many times their size on coding and vision tasks.",
      serverArgs: ["--temp", "0.6", "--top-k", "20", "--top-p", "0.95", "--min-p", "0"],
      overheadMultiplier: 1.1,
      sizes: [
        ModelSize(
          name: "27B",
          parameterCount: 26_883_041_792,
          releaseDate: date(2026, 3, 3),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 67_108_864,
          mmproj: URL(
            string:
              "https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/resolve/main/mmproj-F16.gguf"
          )!,
          mmprojLocalFilename: "Qwen3.5-27B-mmproj-F16.gguf",
          build: ModelBuild(
            quantization: "Q8_0",
            fileSize: 28_595_763_104,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/resolve/main/Qwen3.5-27B-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              quantization: "UD-Q4_K_XL",
              fileSize: 17_621_125_024,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-27B-GGUF/resolve/main/Qwen3.5-27B-UD-Q4_K_XL.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "35B-A3B",
          parameterCount: 34_691_457_024,
          releaseDate: date(2026, 3, 3),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 20_971_520,
          mmproj: URL(
            string:
              "https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF/resolve/main/mmproj-F16.gguf"
          )!,
          mmprojLocalFilename: "Qwen3.5-35B-A3B-mmproj-F16.gguf",
          build: ModelBuild(
            quantization: "Q8_0",
            fileSize: 36_903_139_968,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF/resolve/main/Qwen3.5-35B-A3B-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              quantization: "UD-Q4_K_XL",
              fileSize: 22_241_950_336,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF/resolve/main/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf"
              )!
            )
          ]
        ),
        ModelSize(
          name: "122B-A10B",
          parameterCount: 122_000_000_000,
          releaseDate: date(2026, 3, 3),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 25_165_824,
          mmproj: URL(
            string:
              "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/mmproj-F16.gguf"
          )!,
          mmprojLocalFilename: "Qwen3.5-122B-A10B-mmproj-F16.gguf",
          build: ModelBuild(
            quantization: "Q8_0",
            fileSize: 129_871_935_040,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/Q8_0/Qwen3.5-122B-A10B-Q8_0-00001-of-00004.gguf"
            )!,
            additionalParts: [
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/Q8_0/Qwen3.5-122B-A10B-Q8_0-00002-of-00004.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/Q8_0/Qwen3.5-122B-A10B-Q8_0-00003-of-00004.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/Q8_0/Qwen3.5-122B-A10B-Q8_0-00004-of-00004.gguf"
              )!,
            ]
          ),
          quantizedBuilds: [
            ModelBuild(
              quantization: "UD-Q4_K_XL",
              fileSize: 68_357_580_224,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/UD-Q4_K_XL/Qwen3.5-122B-A10B-UD-Q4_K_XL-00001-of-00003.gguf"
              )!,
              additionalParts: [
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/UD-Q4_K_XL/Qwen3.5-122B-A10B-UD-Q4_K_XL-00002-of-00003.gguf"
                )!,
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3.5-122B-A10B-GGUF/resolve/main/UD-Q4_K_XL/Qwen3.5-122B-A10B-UD-Q4_K_XL-00003-of-00003.gguf"
                )!,
              ]
            )
          ]
        ),
        ModelSize(
          name: "397B-A17B",
          parameterCount: 397_000_000_000,
          releaseDate: date(2026, 3, 3),
          ctxWindow: 262_144,
          ctxBytesPer1kTokens: 31_457_280,
          mmproj: URL(
            string:
              "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/mmproj-F16.gguf"
          )!,
          mmprojLocalFilename: "Qwen3.5-397B-A17B-mmproj-F16.gguf",
          build: ModelBuild(
            quantization: "Q8_0",
            fileSize: 421_507_365_376,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/Q8_0/Qwen3.5-397B-A17B-Q8_0-00001-of-00010.gguf"
            )!,
            additionalParts: [
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/Q8_0/Qwen3.5-397B-A17B-Q8_0-00002-of-00010.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/Q8_0/Qwen3.5-397B-A17B-Q8_0-00003-of-00010.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/Q8_0/Qwen3.5-397B-A17B-Q8_0-00004-of-00010.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/Q8_0/Qwen3.5-397B-A17B-Q8_0-00005-of-00010.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/Q8_0/Qwen3.5-397B-A17B-Q8_0-00006-of-00010.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/Q8_0/Qwen3.5-397B-A17B-Q8_0-00007-of-00010.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/Q8_0/Qwen3.5-397B-A17B-Q8_0-00008-of-00010.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/Q8_0/Qwen3.5-397B-A17B-Q8_0-00009-of-00010.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/Q8_0/Qwen3.5-397B-A17B-Q8_0-00010-of-00010.gguf"
              )!,
            ]
          ),
          quantizedBuilds: [
            ModelBuild(
              quantization: "UD-Q4_K_XL",
              fileSize: 219_216_328_992,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/UD-Q4_K_XL/Qwen3.5-397B-A17B-UD-Q4_K_XL-00001-of-00006.gguf"
              )!,
              additionalParts: [
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/UD-Q4_K_XL/Qwen3.5-397B-A17B-UD-Q4_K_XL-00002-of-00006.gguf"
                )!,
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/UD-Q4_K_XL/Qwen3.5-397B-A17B-UD-Q4_K_XL-00003-of-00006.gguf"
                )!,
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/UD-Q4_K_XL/Qwen3.5-397B-A17B-UD-Q4_K_XL-00004-of-00006.gguf"
                )!,
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/UD-Q4_K_XL/Qwen3.5-397B-A17B-UD-Q4_K_XL-00005-of-00006.gguf"
                )!,
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF/resolve/main/UD-Q4_K_XL/Qwen3.5-397B-A17B-UD-Q4_K_XL-00006-of-00006.gguf"
                )!,
              ]
            )
          ]
        ),
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
            quantization: "Q8_0",
            fileSize: 33_585_495_328,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Nemotron-Nano-3-30B-A3B-GGUF/resolve/main/Nemotron-Nano-3-30B-A3B-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
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
            quantization: "Q8_0",
            fileSize: 3_913_606_144,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-3B-Instruct-2512-GGUF/resolve/main/Ministral-3-3B-Instruct-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
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
            quantization: "Q8_0",
            fileSize: 3_916_269_568,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-3B-Reasoning-2512-GGUF/resolve/main/Ministral-3-3B-Reasoning-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
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
            quantization: "Q8_0",
            fileSize: 9_703_104_512,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-8B-Instruct-2512-GGUF/resolve/main/Ministral-3-8B-Instruct-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
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
            quantization: "Q8_0",
            fileSize: 9_701_376_000,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-8B-Reasoning-2512-GGUF/resolve/main/Ministral-3-8B-Reasoning-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
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
            quantization: "Q8_0",
            fileSize: 14_359_311_264,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-14B-Instruct-2512-GGUF/resolve/main/Ministral-3-14B-Instruct-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
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
            quantization: "Q8_0",
            fileSize: 14_359_309_728,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Ministral-3-14B-Reasoning-2512-GGUF/resolve/main/Ministral-3-14B-Reasoning-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
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
    // MARK: GLM 4.7
    ModelFamily(
      name: "GLM 4.7",
      series: "z",
      description:
        "Zhipu AI's agentic reasoning and coding models. Built for software engineering, browser automation, and multi-turn tool use.",
      serverArgs: nil,
      sizes: [
        ModelSize(
          name: "Flash",
          parameterCount: 29_943_393_920,
          releaseDate: date(2026, 1, 19),
          ctxWindow: 202_752,
          ctxBytesPer1kTokens: 110_886_912,
          build: ModelBuild(
            quantization: "Q8_0",
            fileSize: 31_842_799_232,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/GLM-4.7-Flash-GGUF/resolve/main/GLM-4.7-Flash-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
              quantization: "Q4_K",
              fileSize: 18_244_193_920,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/ggml-org/GLM-4.7-Flash-GGUF/resolve/main/GLM-4.7-Flash-Q4_K.gguf"
              )!
            )
          ]
        )
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
            quantization: "Q8_0",
            fileSize: 25_055_308_352,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Devstral-Small-2-24B-Instruct-2512-GGUF/resolve/main/Devstral-Small-2-24B-Instruct-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
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
            quantization: "Q8_0",
            fileSize: 132_854_938_656,
            downloadUrl: URL(
              string:
                "https://huggingface.co/ggml-org/Devstral-2-123B-Instruct-2512-GGUF/resolve/main/Devstral-2-123B-Instruct-2512-Q8_0.gguf"
            )!
          ),
          quantizedBuilds: [
            ModelBuild(
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
