import AppKit

enum InstalledModelPresenter {
  struct Display {
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
  ) -> Display {
    let isActive = server.isActive(model: model)
    let isLoading = isActive && server.isLoading

    switch status {
    case .downloading(let progress):
      let completedSizeText = ByteFormatters.gbTwoDecimals(progress.completedUnitCount)
      let totalBytes = progress.totalUnitCount > 0 ? progress.totalUnitCount : model.fileSize
      let totalSizeText = ByteFormatters.gbTwoDecimals(totalBytes)

      let metadataText = MetadataLabel.make(
        icon: MetadataLabel.sizeSymbol,
        text: "\(completedSizeText) / \(totalSizeText)"
      )

      return Display(
        title: model.menuTitle,
        metadataText: metadataText,
        progressText: ProgressFormatters.percentText(progress),
        showsCancelButton: true,
        isLoading: isLoading,
        isActive: isActive
      )

    case .installed, .available:
      return Display(
        title: model.menuTitle,
        metadataText: ModelMetadataFormatters.makeMetadataText(for: model),
        progressText: nil,
        showsCancelButton: false,
        isLoading: isLoading,
        isActive: isActive
      )
    }
  }
}
