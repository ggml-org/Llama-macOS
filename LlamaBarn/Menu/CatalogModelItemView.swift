import AppKit
import Foundation

/// Interactive menu item for a downloadable model build shown under an expanded family item.
final class CatalogModelItemView: ItemView {
  private let model: CatalogEntry
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  private let iconView = IconView()
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

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 40) }

  // Only allow highlight for available models.
  // Catalog items should never show downloading or installed states.
  override var highlightEnabled: Bool {
    let status = modelManager.status(for: model)
    guard case .available = status else { return false }
    return true
  }

  override func highlightDidChange(_ highlighted: Bool) {
    // No color changes on hover - catalog models stay with secondary colors
  }

  private func setup() {
    wantsLayer = true
    iconView.imageView.image = NSImage(named: model.icon)
    iconView.inactiveTintColor = Typography.secondaryColor

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

    contentView.addSubview(leading)
    leading.pinToSuperview()

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: Layout.iconViewSize),
      iconView.heightAnchor.constraint(equalToConstant: Layout.iconViewSize),
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

  func refresh() {
    labelField.attributedStringValue = Format.modelName(
      family: model.family,
      size: model.sizeLabel,
      familyColor: Typography.secondaryColor,
      sizeColor: Typography.secondaryColor
    )

    metadataLabel.attributedStringValue = Format.modelMetadata(for: model)

    // Clear highlight if no longer actionable
    if !highlightEnabled { setHighlight(false) }
    needsDisplay = true
  }
}
