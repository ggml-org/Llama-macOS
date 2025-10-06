import AppKit

enum CatalogModelPresenter {
  struct Display {
    enum StatusIcon {
      case installed
      case downloading(percent: Int)
      case available(compatible: Bool)
    }

    let title: String
    let metadataText: NSAttributedString
    let infoTooltip: String?
    let warningTooltip: String?
    let status: StatusIcon
    let progressText: String?
    let rowTooltip: String?
    let isActionable: Bool
    let isCompatible: Bool
  }

  static func isActionable(model: CatalogEntry, status: ModelStatus) -> Bool {
    switch status {
    case .available:
      return Catalog.isModelCompatible(model)
    case .downloading:
      return true
    case .installed:
      return false
    }
  }

  static func makeDisplay(for model: CatalogEntry, status: ModelStatus) -> Display {
    let compatible = Catalog.isModelCompatible(model)
    let actionable = isActionable(model: model, status: status)

    let usableCtx = Catalog.usableCtxWindow(for: model)

    let infoTooltip: String? =
      compatible
      ? nil
      : (Catalog.incompatibilitySummary(model) ?? "not compatible")

    let warningTooltip: String? =
      compatible && usableCtx != nil && usableCtx! < model.ctxWindow
      ? "Can run at reduced context window"
      : nil

    let statusIcon: Display.StatusIcon
    let progressText: String?
    let rowTooltip: String?
    switch status {
    case .installed:
      statusIcon = .installed
      progressText = nil
      rowTooltip = "Already installed"
    case .downloading(let progress):
      statusIcon = .downloading(percent: ProgressFormatters.percent(progress))
      progressText = ProgressFormatters.percentText(progress)
      rowTooltip = nil
    case .available:
      statusIcon = .available(compatible: compatible)
      progressText = nil
      rowTooltip = nil
    }

    let metadataText = makeMetadataText(model: model, compatible: compatible)

    return Display(
      title: model.menuTitle,
      metadataText: metadataText,
      infoTooltip: infoTooltip,
      warningTooltip: warningTooltip,
      status: statusIcon,
      progressText: progressText,
      rowTooltip: rowTooltip,
      isActionable: actionable,
      isCompatible: compatible
    )
  }

  private static func makeMetadataText(
    model: CatalogEntry,
    compatible: Bool
  ) -> NSAttributedString {
    // Incompatible models show only error message in tertiaryColor
    guard compatible else {
      return NSAttributedString(
        string: "Won't run on this device.", attributes: Typography.tertiaryAttributes)
    }

    // Compatible models use shared metadata formatter
    return ModelMetadataFormatters.makeMetadataText(for: model)
  }

}
