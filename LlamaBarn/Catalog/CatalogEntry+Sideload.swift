import Foundation

extension CatalogEntry {

  /// Builds a sideloaded-style `CatalogEntry` from the raw identifying bits
  /// a deeplink install carries. Mirrors the defaults in
  /// `HFCache.buildSideloadedEntry` — same id shape, same icon, same ctx
  /// ceiling, same "no ctxBytesPer1kTokens yet, fit-params fills it in later"
  /// posture. The point of a shared factory is that both producers of the
  /// entry (fresh deeplinks resolving right now; persisted deeplinks being
  /// re-resolved on relaunch) agree on these defaults, so the id identity
  /// promised by `{org}/{repo}:{QUANT}` actually round-trips.
  ///
  /// `mainUrl` is nil for hydrate-time placeholders that haven't been
  /// re-resolved yet; a sentinel `file:///` URL is substituted so the
  /// struct is valid. `downloadModel` will refuse to run against it
  /// (`HFCache.repoDirName` returns nil for non-HF URLs) — the re-resolve
  /// swaps the placeholder for a real entry before the user can click.
  static func sideloadPlaceholder(
    modelId: String,
    repo: String,
    quant: String,
    mainUrl: URL?,
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
      ctxBytesPer1kTokens: 0,  // Filled in async by llama-fit-params post-install
      downloadUrl: mainUrl ?? URL(string: "file:///")!,
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
