import Foundation

extension Model {

  /// Builds a pre-download `Model` for a deeplink-initiated install.
  ///
  /// Mirrors `HFCache.buildSideloadedEntry` (same id shape, 128k ctx ceiling,
  /// `ctxBytesPer1kTokens = 0` "MemProfile fills it in later" posture) so the
  /// row's identity round-trips once the scan surfaces the landed files.
  static func placeholderForDownload(
    modelId: String,
    repo: String,
    quant: String,
    mainUrl: URL,
    additionalParts: [URL],
    mmprojUrl: URL?,
    fileSize: Int64
  ) -> Model {
    let repoDir = "models--" + repo.replacingOccurrences(of: "/", with: "--")
    let parsed = HFRepoParser.parse(repoDir: repoDir)
    let parts = repo.split(separator: "/")
    let org = parsed?.org ?? (parts.first.map(String.init) ?? "")
    let name = parsed?.name ?? (parts.count > 1 ? String(parts[1]) : repo)
    let sizeLabel = parsed?.params ?? quant

    return Model(
      id: modelId,
      family: name,
      size: sizeLabel,
      fileSize: fileSize,
      downloadUrl: mainUrl,
      additionalParts: additionalParts.isEmpty ? nil : additionalParts,
      mmprojUrl: mmprojUrl,
      org: org,
      tags: parsed?.tags ?? [],
      quantization: quant
    )
  }
}
