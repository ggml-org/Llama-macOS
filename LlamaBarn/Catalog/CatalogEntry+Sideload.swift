import Foundation

extension CatalogEntry {

  /// Builds a sideloaded-style `CatalogEntry` for a deeplink install.
  /// Mirrors the defaults in `HFCache.buildSideloadedEntry` (same id shape,
  /// icon, ctx ceiling, "no ctxBytesPer1kTokens yet, MemProfile fills it in
  /// later" posture) so identity round-trips once `scanForSideloaded`
  /// surfaces the landed files post-download.
  static func sideloadPlaceholder(
    modelId: String,
    repo: String,
    quant: String,
    mainUrl: URL,
    additionalParts: [URL],
    mmprojUrl: URL?,
    fileSize: Int64
  ) -> CatalogEntry {
    let repoDir = "models--" + repo.replacingOccurrences(of: "/", with: "--")
    let parsed = HFRepoParser.parse(repoDir: repoDir)
    let parts = repo.split(separator: "/")
    let org = parsed?.org ?? (parts.first.map(String.init) ?? "")
    let name = parsed?.name ?? (parts.count > 1 ? String(parts[1]) : repo)
    let sizeLabel = parsed?.params ?? quant

    return CatalogEntry(
      id: modelId,
      family: name,
      parameterCount: 0,
      size: sizeLabel,
      ctxWindow: 131_072,  // 128k upper bound, clamped by memory budget
      fileSize: fileSize,
      ctxBytesPer1kTokens: 0,  // Filled in async from the MemProfile probe post-install
      downloadUrl: mainUrl,
      additionalParts: additionalParts.isEmpty ? nil : additionalParts,
      mmprojUrl: mmprojUrl,
      serverArgs: [],
      icon: "sideloaded",
      quantization: quant,
      isFullPrecision: false,
      isSideloaded: true,
      org: org,
      tags: parsed?.tags ?? []
    )
  }
}
