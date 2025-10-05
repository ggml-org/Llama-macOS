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
    let actionable: Bool = {
      switch status {
      case .available: return compatible
      case .downloading: return true
      case .installed: return false
      }
    }()

    let usableCtx = Catalog.usableCtxWindow(for: model)

    let contextString: String

    if compatible {
      contextString = {
        if let usable = usableCtx, usable < model.ctxWindow {
          let max = model.ctxWindow
          return "\(TokenFormatters.shortTokens(usable)) of \(TokenFormatters.shortTokens(max))"
        }
        guard model.ctxWindow > 0 else { return "—" }
        return TokenFormatters.shortTokens(model.ctxWindow)
      }()
    } else {
      contextString = "Won't run on this device."
    }

    let infoTooltip: String? =
      compatible
      ? nil
      : (Catalog.incompatibilitySummary(model) ?? "not compatible")

    let (showsWarning, warningTooltip) = makeMaxContextWarning(for: model, compatible: compatible)

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

    let memoryMb = Catalog.runtimeMemoryUsageMb(
      for: model,
      ctxWindowTokens: Double(usableCtx ?? model.ctxWindow)
    )

    let metadataText = makeMetadataText(
      model: model,
      memoryMb: memoryMb,
      contextString: contextString,
      showsWarning: showsWarning
    )

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
    memoryMb: UInt64,
    contextString: String,
    showsWarning: Bool
  ) -> NSAttributedString {
    let line = NSMutableAttributedString()

    line.append(MetadataLabel.make(icon: MetadataLabel.sizeSymbol, text: model.totalSize))
    line.append(MetadataLabel.makeSeparator())
    line.append(
      MetadataLabel.make(
        icon: MetadataLabel.memorySymbol, text: MemoryFormatters.gbOneDecimal(memoryMb)))
    line.append(MetadataLabel.makeSeparator())
    line.append(MetadataLabel.make(icon: MetadataLabel.contextSymbol, text: contextString))

    if showsWarning {
      line.append(MetadataLabel.makeSeparator())
      line.append(MetadataLabel.makeIconOnly(icon: MetadataLabel.warningSymbol))
    }

    return line
  }

  private static func makeMaxContextWarning(
    for model: CatalogEntry,
    compatible: Bool
  ) -> (Bool, String?) {
    guard compatible, model.ctxWindow > 0 else { return (false, nil) }
    let maxTokens = Double(model.ctxWindow)
    if maxTokens <= Catalog.compatibilityCtxWindowTokens {
      return (false, nil)
    }
    let stillFits = Catalog.isModelCompatible(
      model,
      ctxWindowTokens: maxTokens
    )
    guard !stillFits else { return (false, nil) }
    return (true, "Can run at reduced context window")
  }

}
