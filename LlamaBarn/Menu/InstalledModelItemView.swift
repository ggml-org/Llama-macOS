import AppKit
import Foundation

/// Interactive menu item representing a single installed model.
/// Visual states:
/// - Idle: rounded square icon (inactive) + label
/// - Loading: rounded square icon (active)
/// - Running: rounded square icon (active)
final class InstalledModelItemView: ItemView, NSGestureRecognizerDelegate {
  private let model: CatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let membershipChanged: (CatalogEntry) -> Void

  // Subviews
  private let iconView = IconView()
  private let modelNameLabel = Typography.makePrimaryLabel()
  private let metadataLabel = Typography.makeSecondaryLabel()
  private let progressLabel = Typography.makeSecondaryLabel()
  private let cancelImageView = NSImageView()
  private let deleteLabel = Typography.makeSecondaryLabel()

  // Hover handling is provided by MenuItemView
  private var rowClickRecognizer: NSClickGestureRecognizer?
  private var deleteClickRecognizer: NSClickGestureRecognizer?

  init(
    model: CatalogEntry, server: LlamaServer, modelManager: ModelManager,
    membershipChanged: @escaping (CatalogEntry) -> Void
  ) {
    self.model = model
    self.server = server
    self.modelManager = modelManager
    self.membershipChanged = membershipChanged
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 40) }

  private func setup() {
    wantsLayer = true
    iconView.imageView.image = NSImage(named: model.icon)

    progressLabel.alignment = .right

    // Configure cancel button
    if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil) {
      cancelImageView.image = img
    }
    cancelImageView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    cancelImageView.contentTintColor = .systemRed
    cancelImageView.isHidden = true

    deleteLabel.attributedStringValue = makeDeleteButtonText()
    deleteLabel.isHidden = true

    // Spacer expands so trailing visuals sit flush right.
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    modelNameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    modelNameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    progressLabel.setContentHuggingPriority(.required, for: .horizontal)
    progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    // Left: icon aligned with first text line, then two-line text column
    let nameStack = NSStackView(views: [modelNameLabel, metadataLabel])
    nameStack.orientation = .vertical
    nameStack.spacing = 2
    nameStack.alignment = .leading

    let leading = NSStackView(views: [iconView, nameStack])
    leading.orientation = .horizontal
    leading.spacing = 6
    // Center icon vertically against two-line text to match Wi‑Fi menu
    leading.alignment = .centerY

    // Right: status/progress/cancel in a row, delete label positioned separately
    cancelImageView.setContentHuggingPriority(.required, for: .horizontal)
    cancelImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

    let rightStack = NSStackView(views: [progressLabel, cancelImageView])
    rightStack.orientation = .horizontal
    rightStack.spacing = 6
    rightStack.alignment = .centerY

    let rootStack = NSStackView(views: [leading, spacer, rightStack])
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    rootStack.orientation = .horizontal
    rootStack.spacing = 6
    rootStack.alignment = .centerY
    contentView.addSubview(rootStack)

    // Add delete label separately so we can position it at the bottom
    deleteLabel.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(deleteLabel)

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: Layout.iconViewSize),
      iconView.heightAnchor.constraint(equalToConstant: Layout.iconViewSize),

      cancelImageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
      cancelImageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),

      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.progressWidth),
      rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      // Position delete label at the bottom right, aligned with line 2
      deleteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      deleteLabel.bottomAnchor.constraint(equalTo: metadataLabel.bottomAnchor),
    ])
  }

  // Row click recognizer to toggle, letting the delete label handle its own action.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if rowClickRecognizer == nil {
      let click = NSClickGestureRecognizer(target: self, action: #selector(didClickRow))
      click.delegate = self
      addGestureRecognizer(click)
      rowClickRecognizer = click
    }
    if deleteClickRecognizer == nil {
      let click = NSClickGestureRecognizer(target: self, action: #selector(didClickDelete))
      deleteLabel.addGestureRecognizer(click)
      deleteClickRecognizer = click
    }
  }

  @objc private func didClickRow() { toggle() }

  @objc private func didClickDelete() { performDelete() }

  // Prevent row toggle when clicking the delete label.
  func gestureRecognizer(
    _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
  ) -> Bool {
    let loc = event.locationInWindow
    let localPoint = deleteLabel.convert(loc, from: nil)
    if deleteLabel.bounds.contains(localPoint) && !deleteLabel.isHidden {
      return false
    }
    return true
  }

  private func toggle() {
    if modelManager.isInstalled(model) {
      if server.isActive(model: model) { server.stop() } else { server.start(model: model) }
    } else if modelManager.isDownloading(model) {
      modelManager.cancelModelDownload(model)
      membershipChanged(model)
    }
    refresh()
  }

  func refresh() {
    let isActive = server.isActive(model: model)
    let isLoading = isActive && server.isLoading

    modelNameLabel.stringValue = model.fullName
    metadataLabel.attributedStringValue = ModelMetadataFormatters.makeMetadataTextOnly(for: model)

    // Progress and cancel button only for downloading
    if let progress = modelManager.downloadProgress(for: model) {
      modelNameLabel.textColor = Typography.secondaryColor
      progressLabel.stringValue = ProgressFormatters.percentText(progress)
      cancelImageView.isHidden = false
      iconView.inactiveTintColor = Typography.secondaryColor
    } else {
      modelNameLabel.textColor = .controlTextColor
      progressLabel.stringValue = ""
      cancelImageView.isHidden = true
      iconView.inactiveTintColor = Typography.primaryColor
    }

    // Delete button only for installed models on hover
    deleteLabel.isHidden = !modelManager.isInstalled(model) || !isHighlighted

    // Update icon state
    iconView.setLoading(isLoading)
    iconView.isActive = isActive

    needsDisplay = true
  }

  override func highlightDidChange(_ highlighted: Bool) {
    deleteLabel.isHidden = !modelManager.isInstalled(model) || !highlighted
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .systemRed
  }

  private func makeDeleteButtonText() -> NSAttributedString {
    MetadataLabel.makeIconOnly(icon: Symbols.trash, color: Typography.tertiaryColor)
  }

  @objc private func performDelete() {
    guard modelManager.isInstalled(model) else { return }
    modelManager.deleteDownloadedModel(model)
    membershipChanged(model)
  }
}
