import AppKit
import Foundation

/// Interactive menu item for a downloadable model build shown under an expanded family item.
final class CatalogModelItemView: ItemView {
  private let model: CatalogEntry
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  private let iconView = CatalogIconView()
  private let statusIndicator = NSImageView()
  private let labelField = Typography.makePrimaryLabel()
  private let metadataLabel = Typography.makeSecondaryLabel()
  private var rowClickRecognizer: NSClickGestureRecognizer?

  init(
    model: CatalogEntry, modelManager: ModelManager, membershipChanged: @escaping () -> Void
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

  // Only allow highlight for available/compatible models.
  // Catalog items should never show downloading or installed states.
  override var highlightEnabled: Bool {
    let status = modelManager.status(for: model)
    guard case .available = status else { return false }
    return Catalog.isModelCompatible(model)
  }

  override func highlightDidChange(_ highlighted: Bool) {
    iconView.isHighlighted = highlighted
  }

  private func setup() {
    wantsLayer = true
    iconView.imageView.image = NSImage(named: model.icon)
    // Family colors available in model.color but not used for icon background
    // if let bgColor = NSColor.fromHex(model.color) {
    //   iconView.backgroundColor = bgColor.withAlphaComponent(0.11)
    // }
    statusIndicator.symbolConfiguration = .init(pointSize: 12, weight: .regular)

    labelField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Two-line text column (title + metadata)
    let textColumn = NSStackView(views: [labelField, metadataLabel])
    textColumn.orientation = .vertical
    textColumn.alignment = .leading
    textColumn.spacing = 2

    // Leading: icon + text column, aligned to center vertically
    let leading = NSStackView(views: [iconView, textColumn])
    leading.orientation = .horizontal
    leading.alignment = .centerY
    leading.spacing = 6

    // Spacer expands so trailing visuals sit flush right
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Main horizontal row
    let hStack = NSStackView(views: [leading, spacer, statusIndicator])
    hStack.translatesAutoresizingMaskIntoConstraints = false
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY

    contentView.addSubview(hStack)

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: Layout.iconViewSize),
      iconView.heightAnchor.constraint(equalToConstant: Layout.iconViewSize),
      statusIndicator.widthAnchor.constraint(equalToConstant: Layout.uiIconSize),
      statusIndicator.heightAnchor.constraint(equalToConstant: Layout.uiIconSize),
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
    guard highlightEnabled else { return }
    handleAction()
    // No refresh needed - membershipChanged() will trigger catalog rebuild and remove this item
  }

  private func handleAction() {
    // Catalog items only handle the download action for available models.
    // Downloading/installed states are shown in the installed section.
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
  }

  private func makeModelNameAttributedString(compatible: Bool) -> NSAttributedString {
    let result = NSMutableAttributedString()

    // Use tertiary color for incompatible models
    let familyColor = compatible ? Typography.primaryColor : Typography.tertiaryColor
    let sizeColor = compatible ? Typography.secondaryColor : Typography.tertiaryColor

    // Family name in primary style
    let familyAttributes: [NSAttributedString.Key: Any] = [
      .font: Typography.primary,
      .foregroundColor: familyColor,
    ]
    result.append(NSAttributedString(string: model.family, attributes: familyAttributes))

    // Size in primary font with secondary color
    let sizeAttributes: [NSAttributedString.Key: Any] = [
      .font: Typography.primary,
      .foregroundColor: sizeColor,
    ]
    result.append(NSAttributedString(string: " \(model.sizeLabel)", attributes: sizeAttributes))

    return result
  }

  func refresh() {
    let compatible = Catalog.isModelCompatible(model)

    // Title and basic display
    labelField.attributedStringValue = makeModelNameAttributedString(compatible: compatible)

    // Metadata text (second line)
    if compatible {
      metadataLabel.attributedStringValue = ModelMetadataFormatters.makeMetadataTextOnly(for: model)
    } else {
      metadataLabel.attributedStringValue = NSAttributedString(
        string: "Won't run on this device.",
        attributes: Typography.tertiaryAttributes
      )
    }

    // Status-specific display
    // Catalog items only show available models (compatible or incompatible)
    let symbolName = compatible ? "arrow.down" : "nosign"
    statusIndicator.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)

    // No tooltips for catalog items
    toolTip = nil

    // Colors: status indicator only (label color is handled in makeModelNameAttributedString)
    statusIndicator.contentTintColor =
      compatible ? Typography.primaryColor : Typography.tertiaryColor

    // Clear highlight if no longer actionable
    if !highlightEnabled { setHighlight(false) }
    needsDisplay = true
  }
}
