import AppKit
import Foundation

/// Menu row for a downloadable model variant inside a family submenu.
final class VariantMenuItemView: MenuRowView {
  // Central tweak for inline SF Symbol vertical alignment beside secondary text.
  // Negative lowers the glyph relative to the text baseline.
  private static let iconBaselineYOffset: CGFloat = -2
  private static let sizeSymbol: NSImage? = {
    guard
      let image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    else { return nil }
    image.isTemplate = true
    return image
  }()

  private static let contextSymbol: NSImage? = {
    guard
      let image = NSImage(systemSymbolName: "text.word.spacing", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    else { return nil }
    image.isTemplate = true
    return image
  }()

  private static let memorySymbol: NSImage? = {
    guard
      let image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    else { return nil }
    image.isTemplate = true
    return image
  }()

  private static let warningSymbol: NSImage? = {
    guard
      let image = NSImage(
        systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    else { return nil }
    image.isTemplate = true
    return image
  }()

  private let model: ModelCatalogEntry
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  private let statusIndicator = NSImageView()
  private let labelField = NSTextField(labelWithString: "")
  private let infoRow = NSStackView()
  private let sizeLabel = NSTextField(labelWithString: "")
  private let separatorLabel = NSTextField(labelWithString: "•")
  private let ctxLabel = NSTextField(labelWithString: "")
  private let memorySeparatorLabel = NSTextField(labelWithString: "•")
  private let memoryLabel = NSTextField(labelWithString: "")
  private let warningSeparatorLabel = NSTextField(labelWithString: "•")
  private let warningImageView = NSImageView()
  private let progressLabel = NSTextField(labelWithString: "")
  // Background handled by MenuRowView

  // Hover handling provided by MenuRowView

  init(
    model: ModelCatalogEntry, modelManager: ModelManager, membershipChanged: @escaping () -> Void
  ) {
    self.model = model
    self.modelManager = modelManager
    self.membershipChanged = membershipChanged
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 40) }

  // Only allow hover highlight for actionable rows:
  // - available & compatible (can start download)
  // - downloading (can cancel)
  // Not for incompatible variants or already-downloaded ones.
  override var hoverHighlightEnabled: Bool {
    let status = modelManager.getModelStatus(model)
    switch status {
    case .available:
      return ModelCatalog.isModelCompatible(model)
    case .downloading:
      return true
    case .downloaded:
      return false
    }
  }

  private func setup() {
    wantsLayer = true
    statusIndicator.translatesAutoresizingMaskIntoConstraints = false
    statusIndicator.symbolConfiguration = .init(pointSize: 12, weight: .regular)

    labelField.font = MenuTypography.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false
    labelField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let labels = [sizeLabel, ctxLabel, memoryLabel]
    for label in labels {
      label.font = MenuTypography.secondary
      label.textColor = .secondaryLabelColor
      label.lineBreakMode = .byTruncatingTail
      label.translatesAutoresizingMaskIntoConstraints = false
    }

    let separators = [separatorLabel, memorySeparatorLabel, warningSeparatorLabel]
    for separator in separators {
      separator.font = MenuTypography.secondary
      separator.textColor = .tertiaryLabelColor
      separator.translatesAutoresizingMaskIntoConstraints = false
    }
    warningSeparatorLabel.isHidden = true

    warningImageView.translatesAutoresizingMaskIntoConstraints = false
    warningImageView.symbolConfiguration = .init(pointSize: 11, weight: .regular)
    warningImageView.image = Self.warningSymbol
    warningImageView.isHidden = true

    infoRow.orientation = .horizontal
    infoRow.spacing = 4
    infoRow.alignment = .centerY
    infoRow.translatesAutoresizingMaskIntoConstraints = false
    infoRow.addArrangedSubview(sizeLabel)
    infoRow.addArrangedSubview(memorySeparatorLabel)
    infoRow.addArrangedSubview(memoryLabel)
    infoRow.addArrangedSubview(separatorLabel)
    infoRow.addArrangedSubview(ctxLabel)
    infoRow.addArrangedSubview(warningSeparatorLabel)
    infoRow.addArrangedSubview(warningImageView)

    progressLabel.font = MenuTypography.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    // Two-line text column (title + size)
    let textColumn = NSStackView(views: [labelField, infoRow])
    textColumn.translatesAutoresizingMaskIntoConstraints = false
    textColumn.orientation = .vertical
    textColumn.alignment = .leading
    textColumn.spacing = 1

    // Leading group aligns status icon with first line of text
    let leading = NSStackView(views: [statusIndicator, textColumn])
    leading.translatesAutoresizingMaskIntoConstraints = false
    leading.orientation = .horizontal
    leading.alignment = .top
    leading.spacing = 6

    // Main horizontal row with flexible space and trailing visuals (progress only)
    let trailing = NSStackView(views: [progressLabel])
    trailing.translatesAutoresizingMaskIntoConstraints = false
    trailing.orientation = .horizontal
    trailing.alignment = .centerY
    trailing.spacing = 6

    let hStack = NSStackView(views: [leading, NSView(), trailing])
    hStack.translatesAutoresizingMaskIntoConstraints = false
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY

    contentView.addSubview(hStack)

    NSLayoutConstraint.activate([
      statusIndicator.widthAnchor.constraint(equalToConstant: MenuMetrics.smallIconSize),
      statusIndicator.heightAnchor.constraint(equalToConstant: MenuMetrics.smallIconSize),
      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.progressWidth),
      hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      hStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }
  override func mouseDown(with event: NSEvent) {
    guard hoverHighlightEnabled else { return }
    handleAction()
    refresh()
  }

  private func handleAction() {
    let status = modelManager.getModelStatus(model)
    switch status {
    case .available:
      if ModelCatalog.isModelCompatible(model) {
        modelManager.downloadModel(model)
        membershipChanged()
      }
    case .downloading:
      modelManager.cancelModelDownload(model)
      membershipChanged()
    case .downloaded:
      break
    }
  }

  // Hover highlight handled by base class

  func refresh() {
    let status = modelManager.getModelStatus(model)
    let compatible = ModelCatalog.isModelCompatible(model)
    let actionable = hoverHighlightEnabled
    var title = "\(model.displayName)"
    if !model.isFullPrecision {
      title += " \(model.quantization)"
    }
    labelField.stringValue = title

    let sizeString = model.totalSize
    let contextString =
      model.contextLength > 0
      ? TokenFormatters.shortTokens(model.contextLength)
      : "—"
    let memoryEstimate = makeMemoryEstimateString(
      for: model, contextLength: model.contextLength)

    infoRow.toolTip = nil
    if !compatible {
      let reason = ModelCatalog.incompatibilitySummary(model) ?? "not compatible"
      infoRow.toolTip = reason
    }

    let maxContextCompatible: Bool = {
      guard model.contextLength > 0 else { return compatible }
      let maxTokens = Double(model.contextLength)
      if maxTokens <= ModelCatalog.compatibilityContextLengthTokens { return compatible }
      return ModelCatalog.isModelCompatible(model, contextLengthTokens: maxTokens)
    }()
    let needsMaxContextWarning = compatible && !maxContextCompatible
    let maxContextReason: String? =
      needsMaxContextWarning
      ? ModelCatalog.incompatibilitySummary(
        model, contextLengthTokens: Double(model.contextLength))
      : nil

    // Visual affordances:
    // - Incompatible: tertiary (disabled) coloring
    // - Downloaded: dim to indicate non-interactive
    // - Actionable (available or downloading): regular colors
    let infoColor: NSColor
    if !compatible {
      labelField.textColor = .tertiaryLabelColor
      infoColor = .tertiaryLabelColor
    } else if !actionable {
      labelField.textColor = .secondaryLabelColor
      infoColor = .tertiaryLabelColor
    } else {
      labelField.textColor = .labelColor
      infoColor = .secondaryLabelColor
    }
    sizeLabel.attributedStringValue = makeSizeAttributedString(
      sizeString: sizeString, color: infoColor)
    separatorLabel.textColor = infoColor
    ctxLabel.textColor = infoColor
    memorySeparatorLabel.textColor = infoColor
    memoryLabel.textColor = infoColor
    warningSeparatorLabel.textColor = infoColor
    warningImageView.contentTintColor = infoColor
    ctxLabel.attributedStringValue = makeContextAttributedString(
      contextString: contextString, color: infoColor)

    if let memoryEstimate {
      memoryLabel.attributedStringValue = makeMemoryAttributedString(
        memoryString: memoryEstimate, color: infoColor)
      memoryLabel.isHidden = false
      memorySeparatorLabel.isHidden = false
    } else {
      memoryLabel.stringValue = ""
      memoryLabel.isHidden = true
      memorySeparatorLabel.isHidden = true
    }

    if needsMaxContextWarning {
      warningSeparatorLabel.isHidden = false
      warningImageView.isHidden = false
      if let reason = maxContextReason, model.contextLength > 0 {
        let ctxString = TokenFormatters.shortTokens(model.contextLength)
        warningImageView.toolTip = "\(reason) for full \(ctxString) context"
      } else {
        warningImageView.toolTip = "Cannot run at maximum context"
      }
    } else {
      warningSeparatorLabel.isHidden = true
      warningImageView.isHidden = true
      warningImageView.toolTip = nil
    }

    progressLabel.stringValue = ""
    switch status {
    case .downloaded:
      // Installed variants are not clickable in this submenu; show the green check used in family badges.
      statusIndicator.image = NSImage(
        systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
      statusIndicator.contentTintColor = .llamaGreen
      toolTip = "Already installed"
    case .downloading(let progress):
      let pct: Int
      if progress.totalUnitCount > 0 {
        pct = Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
      } else {
        pct = 0
      }
      // Monochrome progress indicator.
      statusIndicator.image = NSImage(
        systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
      statusIndicator.contentTintColor = .secondaryLabelColor
      progressLabel.stringValue = "\(pct)%"
    case .available:
      if compatible {
        statusIndicator.image = NSImage(
          systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        statusIndicator.contentTintColor = .secondaryLabelColor
      } else {
        statusIndicator.image = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)
        // Monochrome disabled/incompatible indicator.
        statusIndicator.contentTintColor = .tertiaryLabelColor
      }
    }
    // If the item is no longer actionable, clear any lingering hover highlight.
    if !hoverHighlightEnabled { setHoverHighlight(false) }
    needsDisplay = true
  }

  private func makeSizeAttributedString(sizeString: String, color: NSColor) -> NSAttributedString {
    let textAttributes: [NSAttributedString.Key: Any] = [
      .font: MenuTypography.secondary,
      .foregroundColor: color,
    ]
    guard let icon = Self.sizeSymbol else {
      return NSAttributedString(string: sizeString, attributes: textAttributes)
    }

    let attachment = NSTextAttachment()
    attachment.image = icon
    // Slight baseline tweak keeps the glyph visually centered beside the text.
    attachment.bounds = CGRect(
      x: 0, y: Self.iconBaselineYOffset, width: icon.size.width, height: icon.size.height)

    let result = NSMutableAttributedString(
      attributedString: NSAttributedString(attachment: attachment))
    result.append(NSAttributedString(string: " \(sizeString)", attributes: textAttributes))
    result.addAttribute(
      .foregroundColor, value: color, range: NSRange(location: 0, length: result.length))
    return result
  }

  private func makeMemoryEstimateString(for model: ModelCatalogEntry, contextLength: Int) -> String?
  {
    guard contextLength > 0 else { return nil }

    let usageMB = ModelCatalog.runtimeMemoryUsageMB(
      for: model, contextLengthTokens: Double(contextLength))
    guard usageMB > 0 else { return nil }

    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB]
    formatter.countStyle = .binary
    let bytes = Int64(usageMB) * 1_048_576
    return formatter.string(fromByteCount: bytes)
  }

  private func makeMemoryAttributedString(memoryString: String, color: NSColor)
    -> NSAttributedString
  {
    let textAttributes: [NSAttributedString.Key: Any] = [
      .font: MenuTypography.secondary,
      .foregroundColor: color,
    ]
    guard let icon = Self.memorySymbol else {
      return NSAttributedString(string: memoryString, attributes: textAttributes)
    }

    let attachment = NSTextAttachment()
    attachment.image = icon
    attachment.bounds = CGRect(
      x: 0, y: Self.iconBaselineYOffset, width: icon.size.width, height: icon.size.height)

    let result = NSMutableAttributedString(
      attributedString: NSAttributedString(attachment: attachment))
    result.append(NSAttributedString(string: " \(memoryString)", attributes: textAttributes))
    result.addAttribute(
      .foregroundColor, value: color, range: NSRange(location: 0, length: result.length))
    return result
  }

  private func makeContextAttributedString(contextString: String, color: NSColor)
    -> NSAttributedString
  {
    let textAttributes: [NSAttributedString.Key: Any] = [
      .font: MenuTypography.secondary,
      .foregroundColor: color,
    ]
    guard let icon = Self.contextSymbol else {
      return NSAttributedString(string: contextString, attributes: textAttributes)
    }

    let attachment = NSTextAttachment()
    attachment.image = icon
    attachment.bounds = CGRect(
      x: 0, y: Self.iconBaselineYOffset, width: icon.size.width, height: icon.size.height)

    let result = NSMutableAttributedString(
      attributedString: NSAttributedString(attachment: attachment))
    result.append(NSAttributedString(string: " \(contextString)", attributes: textAttributes))
    result.addAttribute(
      .foregroundColor, value: color, range: NSRange(location: 0, length: result.length))
    return result
  }
}
