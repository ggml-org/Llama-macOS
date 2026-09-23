import Foundation

extension Model {

  /// Builds a pre-download `Model` for a deeplink-initiated install.
  ///
  /// Mirrors `HFCache.buildSideloadedEntry` (same id shape, 128k ctx ceiling,
  /// `ctxBytesPer1kTokens = 0` "MemProfile fills it in later" posture) so the
  /// row's identity round-trips once the scan surfaces the landed files.
  static func placeholderForDownload(
    modelId: String,
    mainUrl: URL,
    additionalParts: [URL],
    mmprojUrl: URL?,
    mtpUrl: URL?,
    fileSize: Int64
  ) -> Model {
    Model(
      id: modelId,
      fileSize: fileSize,
      downloadUrl: mainUrl,
      additionalParts: additionalParts.isEmpty ? nil : additionalParts,
      mmprojUrl: mmprojUrl,
      mtpUrl: mtpUrl
    )
  }
}
