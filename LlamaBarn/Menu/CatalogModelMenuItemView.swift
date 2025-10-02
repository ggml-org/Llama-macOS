import AppKit
import Foundation

/// Menu row for a downloadable model variant inside a family submenu.
final class CatalogModelMenuItemView: MenuRowView {
  // Central tweak for inline SF Symbol vertical alignment beside secondary text.
  // Negative lowers the glyph relative to the text baseline.
  private static let iconBaselineYOffset: CGFloat = -2

  private let model: CatalogEntry
  private unowned let modelManager: Manager
  private let membershipChanged: () -> Void

  private let statusIndicator = NSImageView()
  private let labelField = NSTextField(labelWithString: "")
  private let metadataLabel = NSTextField(labelWithString: "")
  private let progressLabel = NSTextField(labelWithString: "")
  private var rowClickRecognizer: NSClickGestureRecognizer?
  // Background handled by MenuRowView

  // Hover handling provided by MenuRowView

  init(
    model: CatalogEntry, modelManager: Manager, membershipChanged: @escaping () -> Void
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

  // Only allow hover highlight for actionable rows (available/compatible or downloading).
  override var hoverHighlightEnabled: Bool {
    VariantRowPresenter.isActionable(model: model, status: modelManager.getModelStatus(model))
  }

  private func setup() {
    wantsLayer = true
    statusIndicator.translatesAutoresizingMaskIntoConstraints = false
    statusIndicator.symbolConfiguration = .init(pointSize: 12, weight: .regular)

    labelField.font = Typography.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false
    labelField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    metadataLabel.font = Typography.secondary
    metadataLabel.textColor = .secondaryLabelColor
    metadataLabel.lineBreakMode = .byTruncatingTail
    metadataLabel.translatesAutoresizingMaskIntoConstraints = false

    progressLabel.font = Typography.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    // Two-line text column (title + metadata)
    let textColumn = NSStackView(views: [labelField, metadataLabel])
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
      statusIndicator.widthAnchor.constraint(equalToConstant: Metrics.smallIconSize),
      statusIndicator.heightAnchor.constraint(equalToConstant: Metrics.smallIconSize),
      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.progressWidth),
      hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      hStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard rowClickRecognizer == nil else { return }

    let click = NSClickGestureRecognizer(target: self, action: #selector(didClickRow(_:)))
    click.buttonMask = 0x1  // Left mouse button only
    addGestureRecognizer(click)
    rowClickRecognizer = click
  }

  @objc private func didClickRow(_ recognizer: NSClickGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    let location = recognizer.location(in: self)
    guard bounds.contains(location) else { return }
    guard hoverHighlightEnabled else { return }
    handleAction()
    refresh()
  }

  private func handleAction() {
    let status = modelManager.getModelStatus(model)
    switch status {
    case .available:
      // The `hoverHighlightEnabled` check already covers compatibility, but we could also check here.
      do {
        try modelManager.downloadModel(model)
        membershipChanged()
      } catch {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = error.localizedDescription
        if let error = error as? LocalizedError, let recoverySuggestion = error.recoverySuggestion {
          alert.informativeText = recoverySuggestion
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
    let display = VariantRowPresenter.makeDisplay(for: model, status: status)

    labelField.stringValue = display.title
    labelField.textColor = display.titleColor

    metadataLabel.attributedStringValue = makeMetadataLine(from: display)
    metadataLabel.toolTip = combinedTooltip(
      info: display.infoTooltip, warning: display.warningTooltip)

    switch display.status {
    case .downloaded:
      statusIndicator.image = NSImage(
        systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
      statusIndicator.contentTintColor = .llamaGreen
    case .downloading:
      statusIndicator.image = NSImage(
        systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
      statusIndicator.contentTintColor = .secondaryLabelColor
    case .available(let compatible):
      if compatible {
        statusIndicator.image = NSImage(
          systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        statusIndicator.contentTintColor = .secondaryLabelColor
      } else {
        statusIndicator.image = NSImage(
          systemSymbolName: "nosign", accessibilityDescription: nil)
        statusIndicator.contentTintColor = .tertiaryLabelColor
      }
    }

    progressLabel.stringValue = display.progressText ?? ""
    toolTip = display.rowTooltip

    // If the item is no longer actionable, clear any lingering hover highlight.
    if !display.isActionable { setHoverHighlight(false) }
    needsDisplay = true
  }

  private func makeMetadataLine(from display: VariantRowPresenter.DisplayData) -> NSAttributedString
  {
    let line = NSMutableAttributedString()

    line.append(
      IconLabelFormatter.make(
        icon: IconLabelFormatter.sizeSymbol,
        text: display.sizeText,
        color: display.infoColor,
        baselineOffset: Self.iconBaselineYOffset
      )
    )

    line.append(MetadataSeparator.make(color: display.infoColor))

    if display.compatible {
      line.append(
        IconLabelFormatter.make(
          icon: IconLabelFormatter.contextSymbol,
          text: display.contextText,
          color: display.infoColor,
          baselineOffset: Self.iconBaselineYOffset
        )
      )
    } else {
      line.append(
        NSAttributedString(
          string: display.contextText,
          attributes: [
            .font: Typography.secondary,
            .foregroundColor: display.infoColor,
          ]
        )
      )
    }

    if display.showsWarning {
      line.append(MetadataSeparator.make(color: display.infoColor))
      line.append(
        IconLabelFormatter.makeIconOnly(
          icon: MetadataIcons.warningSymbol,
          color: display.infoColor,
          baselineOffset: MetadataIcons.warningBaselineOffset
        )
      )
    }

    return line
  }

  private func combinedTooltip(info: String?, warning: String?) -> String? {
    switch (info, warning) {
    case (nil, nil):
      return nil
    case (let info?, nil):
      return info
    case (nil, let warning?):
      return warning
    case (let info?, let warning?):
      return "\(info)\n\(warning)"
    }
  }
}
