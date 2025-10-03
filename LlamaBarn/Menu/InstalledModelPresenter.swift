import AppKit

enum InstalledModelPresenter {
  struct DisplayData {
    let title: String
    let metadataText: NSAttributedString
    let progressText: String?
    let showsCancelButton: Bool
    let isLoading: Bool
    let isActive: Bool
  }

  static func makeDisplay(
    for model: CatalogEntry,
    status: ModelStatus,
    server: LlamaServer
  ) -> DisplayData {
    let title = makeTitle(for: model)
    let isActive = server.isActive(model: model)
    let isLoading = isActive && server.isLoading
    let isRunning = isActive && server.isRunning

    switch status {
    case .downloading(let progress):
      let percent =
        progress.totalUnitCount > 0
        ? Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
        : 0

      let completedSizeText = ByteFormatters.gbTwoDecimals(progress.completedUnitCount)
      let totalBytes = progress.totalUnitCount > 0 ? progress.totalUnitCount : model.fileSize
      let totalSizeText = ByteFormatters.gbTwoDecimals(totalBytes)

      let metadataText = MetadataLabel.make(
        icon: MetadataLabel.sizeSymbol,
        text: "\(completedSizeText) / \(totalSizeText)"
      )

      return DisplayData(
        title: title,
        metadataText: metadataText,
        progressText: "\(percent)%",
        showsCancelButton: true,
        isLoading: isLoading,
        isActive: isRunning
      )

    case .downloaded, .available:
      let metadataText = makeMetadataText(
        for: model,
        isRunning: isRunning,
        memoryUsageMB: server.memoryUsageMB
      )

      return DisplayData(
        title: title,
        metadataText: metadataText,
        progressText: nil,
        showsCancelButton: false,
        isLoading: isLoading,
        isActive: isRunning
      )
    }
  }

  private static func makeTitle(for model: CatalogEntry) -> String {
    var title = model.displayName
    if !model.isFullPrecision,
      let quantLabel = QuantizationFormatters.short(model.quantization).nilIfEmpty
    {
      title += "-\(quantLabel)"
    }
    return title
  }

  private static func makeMetadataText(
    for model: CatalogEntry,
    isRunning: Bool,
    memoryUsageMB: Double
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    result.append(MetadataLabel.make(icon: MetadataLabel.sizeSymbol, text: model.totalSize))

    if let recommendedContext = Catalog.recommendedContextLength(for: model) {
      result.append(MetadataLabel.makeSeparator())
      result.append(
        MetadataLabel.make(
          icon: MetadataLabel.contextSymbol,
          text: TokenFormatters.shortTokens(recommendedContext)
        ))
    }

    if isRunning, let memoryText = MemoryFormatters.runtime(memoryUsageMB) {
      result.append(MetadataLabel.makeSeparator())
      result.append(MetadataLabel.make(icon: MetadataLabel.memorySymbol, text: memoryText))
    }

    return result
  }
}
