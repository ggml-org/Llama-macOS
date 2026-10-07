import Foundation

/// A speculative-decoding draft head the app drives: a small extra network
/// that drafts the next few tokens cheaply, which llama-server then verifies
/// against the main weights in one pass. Both kinds borrow the target model's
/// embeddings and output projection, so neither runs as a model on its own.
///
/// Only models trained with a head have one -- the app can't add it. A repo
/// ships it as a sidecar GGUF named by its kind's prefix (`mtp-….gguf`,
/// `dflash-….gguf`); an MTP head can also be embedded in the main weights.
enum DraftHead: String, Codable {
  /// Multi-token prediction: the head predicts a few tokens ahead.
  case mtp
  /// Block-diffusion drafting: the head fills a whole block of tokens at once.
  case dflash

  /// Kinds in order of preference, for repos that ship more than one head.
  /// DFlash wins: on Qwen3.8-27B (Q8_0, M5 Max, engine b11429) it generated
  /// 35-50% faster than MTP, and the llama.cpp maintainers recommend it over
  /// MTP whenever a model has both. Models that ship only an MTP head keep it.
  static let preferenceOrder: [DraftHead] = [.dflash, .mtp]

  /// The sidecar's filename prefix -- the convention llama.cpp keys on when it
  /// resolves heads shipped beside a model (`find_best_sibling` callers in
  /// `common/download.cpp`).
  var sidecarPrefix: String {
    switch self {
    case .mtp: "mtp-"
    case .dflash: "dflash-"
    }
  }

  /// The kind of the sidecar at `path`, judged by its basename; nil when it
  /// isn't a draft-head sidecar we drive. Accepts full repo-relative paths.
  init?(sidecarPath path: String) {
    let name = (path as NSString).lastPathComponent.lowercased()
    guard name.hasSuffix(".gguf"),
      let kind = Self.preferenceOrder.first(where: { name.hasPrefix($0.sidecarPrefix) })
    else { return nil }
    self = kind
  }

  /// The `spec-type` value that tells llama-server to draft with this head.
  var specType: String {
    switch self {
    case .mtp: "draft-mtp"
    case .dflash: "draft-dflash"
    }
  }

  /// Cap on tokens drafted per step (`spec-draft-n-max`), the values the
  /// llama.cpp maintainers recommend. MTP only predicts a few tokens ahead
  /// reliably, so drafting deeper wastes compute on tokens the target rejects;
  /// DFlash drafts a block at a time and stays accurate further out.
  var draftNMax: Int {
    switch self {
    case .mtp: 3
    case .dflash: 7
    }
  }

  /// Name shown in the model row's chip.
  var label: String {
    switch self {
    case .mtp: "MTP"
    case .dflash: "DFlash"
    }
  }
}
