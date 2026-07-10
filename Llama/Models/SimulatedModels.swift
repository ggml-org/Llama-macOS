#if DEBUG
  import Foundation

  /// A DEBUG-only fixture that populates the "Installed" list with a large,
  /// realistic set of models — so the menu's long-list layout, scrolling,
  /// brand logos, vision/MTP badges, "estimating...", and compatibility states
  /// can be worked on without downloading any weights.
  ///
  /// The list is hand-curated rather than derived from the web catalog: it's a
  /// controlled, offline, deterministic test bed, so the entries are grouped by
  /// the row state each one is here to exercise (see the comments). That control
  /// is the point — it deliberately includes states the catalog never expresses
  /// (MTP heads, pending mem profiles, a too-big-to-run build), so each can be
  /// seen rendering. The numbers mirror common real `ggml-org` / `unsloth` GGUF
  /// repos closely enough to look right; they don't need to be exact.
  ///
  /// Enable it on the dev build with:
  ///
  ///   defaults write app.llama.Llama.dev simulateModels -bool YES
  ///
  /// and remove it with `defaults delete app.llama.Llama.dev simulateModels`.
  /// When set, `ModelManager.refreshDownloadedModels()` skips the real HF-cache
  /// scan and the mem-profile probes entirely and injects this list instead —
  /// nothing touches `models.ini` or the server, so the simulation is purely a
  /// UI surface. Run/delete actions on these rows won't do anything useful
  /// (there are no files behind them); that's expected.
  enum SimulatedModels {
    /// Whether the simulated list should replace the real cache scan.
    static var isEnabled: Bool {
      UserDefaults.standard.bool(forKey: "simulateModels")
    }

    /// The simulated installed models. `ModelManager` re-sorts them through
    /// `Model.displayOrder`, so the array order here doesn't reach the UI — the
    /// entries are instead grouped by the row state each one exercises, so it's
    /// clear what coverage we'd lose by removing one.
    static var all: [Model] {
      [
        // Common dense models — brand logos, plus the fallback symbol for Llama.
        make(
          org: "unsloth", repo: "Gemma-4-E4B-it-GGUF", family: "Gemma 4 E4B",
          quant: "Q4_K_M", fileGB: 5.0, memGB: 5.7),
        make(
          org: "ggml-org", repo: "Meta-Llama-3.1-8B-Instruct-GGUF",
          family: "Meta-Llama 3.1", quant: "Q4_K_M",
          fileGB: 6.0, memGB: 6.4),
        make(
          org: "ggml-org", repo: "gpt-oss-20b-GGUF", family: "gpt-oss",
          quant: "MXFP4", fileGB: 12.1, memGB: 13.0),
        make(
          org: "unsloth", repo: "GLM-4.7-Flash-GGUF", family: "GLM 4.7 Flash",
          quant: "Q4_K_M", fileGB: 17.5, memGB: 18.3),

        // Toy sizes, plus near-identical rows disambiguated by quant chip and org prefix.
        make(
          org: "ggml-org", repo: "Qwen3-0.6B-GGUF", family: "Qwen3",
          quant: "Q4_K_M", fileGB: 0.4, memGB: 1.1),
        make(
          org: "ggml-org", repo: "Qwen3-0.6B-GGUF", family: "Qwen3",
          quant: "Q8_0", fileGB: 0.8, memGB: 1.5),
        make(
          org: "unsloth", repo: "Qwen3-0.6B-GGUF", family: "Qwen3",
          quant: "Q4_K_M", fileGB: 0.4, memGB: 1.2),
        make(
          org: "ggml-org", repo: "Qwen3-1.7B-GGUF", family: "Qwen3",
          quant: "Q4_K_M", fileGB: 1.3, memGB: 1.9),

        // Mid-size dense models — the comfortable-fit case.
        make(
          org: "ggml-org", repo: "Qwen2.5-Coder-7B-GGUF", family: "Qwen2.5-Coder",
          quant: "Q8_0", fileGB: 8.1, memGB: 8.1),
        make(
          org: "unsloth", repo: "Qwen3.5-9B-GGUF", family: "Qwen3.5",
          quant: "Q4_K_M", fileGB: 5.7, memGB: 6.0),

        // MoE (A3B) builds — resident mem far below file size (active experts only).
        make(
          org: "ggml-org", repo: "Qwen3-30B-A3B-GGUF", family: "Qwen3",
          quant: "Q8_0", fileGB: 32.5, memGB: 30.9),
        make(
          org: "ggml-org", repo: "Qwen3-Coder-30B-A3B-Instruct-GGUF",
          family: "Qwen3-Coder", quant: "Q8_0",
          fileGB: 32.5, memGB: 30.9),
        make(
          org: "ggml-org", repo: "Qwen3.6-35B-A3B-GGUF", family: "Qwen3.6",
          quant: "Q8_0", fileGB: 36.9, memGB: 35.0),

        // MTP sidecar variants — a separate draft head.
        make(
          org: "ggml-org", repo: "Qwen3.6-27B-MTP-GGUF", family: "Qwen3.6",
          quant: "Q8_0", fileGB: 29.0, memGB: 28.0, mtp: true),
        make(
          org: "unsloth", repo: "Qwen3.6-35B-A3B-MTP-GGUF", family: "Qwen3.6",
          quant: "Q4_K_M", fileGB: 22.7, memGB: 21.7, mtp: true),

        // Vision model — mmproj sidecar drives the eyeglasses badge.
        make(
          org: "ggml-org", repo: "Qwen2.5-VL-7B-Instruct-GGUF", family: "Qwen2.5-VL",
          quant: "Q4_K_M", fileGB: 6.0, memGB: 6.5,
          vision: true),

        // Awaiting the mem-profile probe — renders "estimating...".
        make(
          org: "ggml-org", repo: "Qwen3.6-27B-GGUF", family: "Qwen3.6",
          quant: "Q8_0", fileGB: 28.6, memGB: nil),
        make(
          org: "unsloth", repo: "Qwen3.5-122B-A10B-GGUF", family: "Qwen3.5",
          quant: "Q4_K_M", fileGB: 0.0, memGB: nil),

        // Too large for most Macs — the incompatible row state.
        make(
          org: "unsloth", repo: "Mistral-Medium-3.5-128B-GGUF",
          family: "Mistral-Medium 3.5", quant: "Q4_K_M",
          fileGB: 75.7, memGB: 72.2),

        // Embedding model — different role; lowercase family guards the sort.
        make(
          org: "ggml-org", repo: "embeddinggemma-300m-GGUF", family: "embeddinggemma",
          quant: "Q8_0", fileGB: 0.6, memGB: 0.8),
      ]
    }

    /// Builds one fixture `Model`. `memGB == nil` leaves `ctxBytesPer1kTokens`
    /// at 0 so the row shows "estimating..."; otherwise `memGB` becomes the
    /// measured resident weight memory and a plausible KV footprint is attached.
    private static func make(
      org: String, repo: String, family: String, quant: String,
      fileGB: Double, memGB: Double?,
      mtp: Bool = false, vision: Bool = false
    ) -> Model {
      // A placeholder file URL keyed on the repo — never read, but it gives
      // each entry a stable id and a non-empty `downloadUrl` like real models.
      let url = URL(fileURLWithPath: "/dev/null/\(org)/\(repo)")
      return Model(
        // Real ids go through the shared grammar (native shortening, -GGUF
        // stripping) — the fixture must too, now that rows display the id.
        id: Model.makeId(org: org, repo: repo, tag: quant),
        family: family,
        fileSize: Int64(fileGB * 1_000_000_000),
        // 0 => pending probe ("estimating..."); ~150 KB per 1k tokens is a
        // representative KV-cache footprint for these model sizes.
        ctxBytesPer1kTokens: memGB == nil ? 0 : 150_000,
        residentBytes: Int((memGB ?? 0) * 1_000_000_000),
        downloadUrl: url,
        mmprojUrl: vision ? url : nil,
        mtpUrl: mtp ? url : nil,
        org: org)
    }
  }
#endif
