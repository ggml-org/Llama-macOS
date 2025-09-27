import Foundation

private typealias ModelFamily = ModelCatalog.ModelFamily
private typealias Model = ModelCatalog.Model
private typealias ModelBuild = ModelCatalog.ModelBuild

enum ModelCatalogFamilies {
  static let families: [ModelCatalog.ModelFamily] = [
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
          contextLength: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "deepseek-r1-0528-qwen3-8b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 8_709_519_872,
            ctxFootprint: 150_994_944,
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
              ctxFootprint: 150_994_944,
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
          contextLength: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gpt-oss-20b-mxfp4",
            quantization: "mxfp4",
            isFullPrecision: true,
            fileSize: 12_109_566_560,
            ctxFootprint: 25_165_824,
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
          contextLength: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gpt-oss-120b-mxfp4",
            quantization: "mxfp4",
            isFullPrecision: true,
            fileSize: 63_387_346_464,
            ctxFootprint: 37_748_736,
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
      models: [
        Model(
          label: "27B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 24))!,
          contextLength: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3-qat-27b",
            quantization: "Q4_0",
            isFullPrecision: true,
            fileSize: 15_908_791_488,
            ctxFootprint: 83_886_080,
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
          contextLength: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3-qat-12b",
            quantization: "Q4_0",
            isFullPrecision: true,
            fileSize: 7_131_017_792,
            ctxFootprint: 67_108_864,
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
          contextLength: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3-qat-4b",
            quantization: "Q4_0",
            isFullPrecision: true,
            fileSize: 2_526_080_992,
            ctxFootprint: 20_971_520,
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
          contextLength: 131_072,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3-qat-1b",
            quantization: "Q4_0",
            isFullPrecision: true,
            fileSize: 720_425_600,
            ctxFootprint: 4_194_304,
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
          contextLength: 32_768,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3-qat-270m",
            quantization: "Q4_0",
            isFullPrecision: true,
            fileSize: 241_410_624,
            ctxFootprint: 3_145_728,
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
          contextLength: 32_768,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3n-e4b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 7_353_292_256,
            ctxFootprint: 14_680_064,
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
              ctxFootprint: 14_680_064,
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
          contextLength: 32_768,
          serverArgs: nil,
          build: ModelBuild(
            id: "gemma-3n-e2b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 4_788_112_064,
            ctxFootprint: 12_582_912,
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
              ctxFootprint: 12_582_912,
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
      models: [
        Model(
          label: "30B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 31))!,
          contextLength: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-coder-30b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 32_483_935_392,
            ctxFootprint: 100_663_296,
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
              ctxFootprint: 100_663_296,
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
      name: "Qwen3 2507",
      series: "qwen",
      blurb:
        "Alibaba's latest Qwen3 refresh focused on instruction following, multilingual coverage, and long contexts across sizes.",
      serverArgs: nil,
      models: [
        Model(
          label: "235B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          contextLength: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-2507-235b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 249_940_106_336,
            ctxFootprint: 197_132_288,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Instruct-2507-Q8_0-00001-of-00006.gguf"
            )!,
            additionalParts: [
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Instruct-2507-Q8_0-00002-of-00006.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Instruct-2507-Q8_0-00003-of-00006.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Instruct-2507-Q8_0-00004-of-00006.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Instruct-2507-Q8_0-00005-of-00006.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Instruct-2507-Q8_0-00006-of-00006.gguf"
              )!,
            ],
            serverArgs: []
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-2507-235b",
              quantization: "Q4_K_M",
              isFullPrecision: false,
              fileSize: 142_154_074_880,
              ctxFootprint: 197_132_288,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Q4_K_M/Qwen3-235B-A22B-Instruct-2507-Q4_K_M-00001-of-00003.gguf"
              )!,
              additionalParts: [
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Q4_K_M/Qwen3-235B-A22B-Instruct-2507-Q4_K_M-00002-of-00003.gguf"
                )!,
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF/resolve/main/Q4_K_M/Qwen3-235B-A22B-Instruct-2507-Q4_K_M-00003-of-00003.gguf"
                )!,
              ],
              serverArgs: []
            )
          ]
        ),
        Model(
          label: "30B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          contextLength: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-2507-30b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 32_483_932_576,
            ctxFootprint: 100_663_296,
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
              ctxFootprint: 100_663_296,
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
          contextLength: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-2507-4b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 4_280_405_600,
            ctxFootprint: 150_994_944,
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
              ctxFootprint: 150_994_944,
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
      name: "Qwen3 2507 Thinking",
      series: "qwen",
      blurb:
        "Qwen3 models biased toward deliberate reasoning and step‑by‑step answers; useful for analysis and planning tasks.",
      serverArgs: nil,
      models: [
        Model(
          label: "235B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          contextLength: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-2507-thinking-235b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 249_940_106_368,
            ctxFootprint: 197_132_288,
            downloadUrl: URL(
              string:
                "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Thinking-2507-Q8_0-00001-of-00006.gguf"
            )!,
            additionalParts: [
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Thinking-2507-Q8_0-00002-of-00006.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Thinking-2507-Q8_0-00003-of-00006.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Thinking-2507-Q8_0-00004-of-00006.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Thinking-2507-Q8_0-00005-of-00006.gguf"
              )!,
              URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Q8_0/Qwen3-235B-A22B-Thinking-2507-Q8_0-00006-of-00006.gguf"
              )!,
            ],
            serverArgs: []
          ),
          quantizedBuilds: [
            ModelBuild(
              id: "qwen3-2507-thinking-235b",
              quantization: "Q4_K_M",
              isFullPrecision: false,
              fileSize: 142_154_074_880,
              ctxFootprint: 197_132_288,
              downloadUrl: URL(
                string:
                  "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Q4_K_M/Qwen3-235B-A22B-Thinking-2507-Q4_K_M-00001-of-00003.gguf"
              )!,
              additionalParts: [
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Q4_K_M/Qwen3-235B-A22B-Thinking-2507-Q4_K_M-00002-of-00003.gguf"
                )!,
                URL(
                  string:
                    "https://huggingface.co/unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF/resolve/main/Q4_K_M/Qwen3-235B-A22B-Thinking-2507-Q4_K_M-00003-of-00003.gguf"
                )!,
              ],
              serverArgs: []
            )
          ]
        ),
        Model(
          label: "30B",
          releaseDate: Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 1))!,
          contextLength: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-2507-thinking-30b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 32_483_932_576,
            ctxFootprint: 100_663_296,
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
              ctxFootprint: 100_663_296,
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
          contextLength: 262_144,
          serverArgs: nil,
          build: ModelBuild(
            id: "qwen3-2507-thinking-4b-q8",
            quantization: "Q8_0",
            isFullPrecision: true,
            fileSize: 4_280_405_632,
            ctxFootprint: 150_994_944,
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
              ctxFootprint: 150_994_944,
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
