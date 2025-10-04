import AppKit
import Foundation

/// Interactive menu item for a downloadable model build inside a family submenu.
final class CatalogModelItemView: ItemView {
  private let model: CatalogEntry
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  private let statusIndicator = NSImageView()
  private let labelField = Typography.makePrimaryLabel()
  private let metadataLabel = Typography.makeSecondaryLabel()
  private let progressLabel = Typography.makeSecondaryLabel()
  private var rowClickRecognizer: NSClickGestureRecognizer?
  // Background handled by MenuItemView

  // Hover handling provided by MenuItemView

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

  // Only allow hover highlight for actionable rows (available/compatible or downloading).
  override var hoverHighlightEnabled: Bool {
    CatalogModelPresenter.isActionable(model: model, status: modelManager.status(for: model))
  }

  private func setup() {
    wantsLayer = true
    statusIndicator.symbolConfiguration = .init(pointSize: 12, weight: .regular)

    labelField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Configure metadata label (second line showing size, context, warnings)
    // Contains all metadata fields in a single attributed string (e.g., "📦 4.28 GB • 🧠 84k")

    progressLabel.alignment = .right

    // Two-line text column (title + metadata)
    let textColumn = NSStackView(views: [labelField, metadataLabel])
    textColumn.orientation = .vertical
    textColumn.alignment = .leading
    textColumn.spacing = 1

    // Leading group aligns status icon with first line of text
    let leading = NSStackView(views: [statusIndicator, textColumn])
    leading.orientation = .horizontal
    leading.alignment = .top
    leading.spacing = 6

    // Main horizontal row with flexible space and trailing progress label
    let hStack = NSStackView(views: [leading, NSView(), progressLabel])
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
    let status = modelManager.status(for: model)
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
    case .installed:
      break
    }
  }

  // Hover highlight handled by base class

  func refresh() {
    let status = modelManager.status(for: model)
    let display = CatalogModelPresenter.makeDisplay(for: model, status: status)

    labelField.stringValue = display.title

    metadataLabel.attributedStringValue = makeMetadataLine(from: display)
    metadataLabel.toolTip = combinedTooltip(
      info: display.infoTooltip, warning: display.warningTooltip)

    // Update status indicator icon
    let symbolName =
      switch display.status {
      case .installed: "checkmark.circle"
      case .downloading: "arrow.down.circle"
      case .available(let compatible): compatible ? "arrow.down.circle" : "nosign"
      }
    statusIndicator.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    statusIndicator.contentTintColor = .labelColor

    progressLabel.stringValue = display.progressText ?? ""
    toolTip = display.rowTooltip

    // If the item is no longer actionable, clear any lingering hover highlight.
    if !display.isActionable { setHoverHighlight(false) }
    needsDisplay = true
  }

  private func makeMetadataLine(from display: CatalogModelPresenter.Display)
    -> NSAttributedString
  {
    let line = NSMutableAttributedString()

    line.append(MetadataLabel.make(icon: MetadataLabel.sizeSymbol, text: display.sizeText))
    line.append(MetadataLabel.makeSeparator())
    line.append(MetadataLabel.make(icon: MetadataLabel.memorySymbol, text: display.memoryText))
    line.append(MetadataLabel.makeSeparator())
    line.append(MetadataLabel.make(icon: MetadataLabel.contextSymbol, text: display.contextText))

    if display.showsWarning {
      line.append(MetadataLabel.makeSeparator())
      line.append(MetadataLabel.makeIconOnly(icon: MetadataLabel.warningSymbol))
    }

    return line
  }

  private func combinedTooltip(info: String?, warning: String?) -> String? {
    [info, warning].compactMap { $0 }.joined(separator: "\n").nilIfEmpty
  }
}
