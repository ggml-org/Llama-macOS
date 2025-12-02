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
  private let deleteImageView = NSImageView()

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

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 40) }

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

    // Configure delete button
    deleteImageView.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
    deleteImageView.contentTintColor = .tertiaryLabelColor
    deleteImageView.symbolConfiguration = .init(
      pointSize: Layout.metadataIconSize, weight: .regular)
    deleteImageView.isHidden = true

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
    rootStack.orientation = .horizontal
    rootStack.spacing = 6
    rootStack.alignment = .centerY
    contentView.addSubview(rootStack)

    // Add delete button separately so we can position it at the bottom
    deleteImageView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(deleteImageView)

    rootStack.pinToSuperview()

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: Layout.iconViewSize),
      iconView.heightAnchor.constraint(equalToConstant: Layout.iconViewSize),

      cancelImageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
      cancelImageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),

      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.progressWidth),

      // Position delete button at the bottom right, aligned with line 2
      deleteImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      deleteImageView.centerYAnchor.constraint(equalTo: metadataLabel.centerYAnchor),
      deleteImageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.metadataIconSize),
      deleteImageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.metadataIconSize),
    ])
  }

  // Row click recognizer to toggle, letting the delete button handle its own action.
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
      deleteImageView.addGestureRecognizer(click)
      deleteClickRecognizer = click
    }
  }

  @objc private func didClickRow() { toggle() }

  @objc private func didClickDelete() { performDelete() }

  // Prevent row toggle when clicking the delete button.
  func gestureRecognizer(
    _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
  ) -> Bool {
    let loc = event.locationInWindow
    let localPoint = deleteImageView.convert(loc, from: nil)
    if deleteImageView.bounds.contains(localPoint) && !deleteImageView.isHidden {
      return false
    }
    return true
  }

  private func toggle() {
    if modelManager.isInstalled(model) {
      if server.isActive(model: model) {
        server.stop()
      } else {
        let maximizeContext = NSEvent.modifierFlags.contains(.option)
        server.start(model: model, maximizeContext: maximizeContext)
      }
    } else if modelManager.isDownloading(model) {
      modelManager.cancelModelDownload(model)
      membershipChanged(model)
    }
    refresh()
  }

  func refresh() {
    let isActive = server.isActive(model: model)
    let isLoading = isActive && server.isLoading

    // Progress and cancel button only for downloading
    let isDownloading = modelManager.downloadProgress(for: model) != nil

    // Use tertiary for downloading, primary for running, secondary for installed
    let familyColor: NSColor
    if isDownloading {
      familyColor = Typography.tertiaryColor
    } else if isActive && !isLoading {
      familyColor = Typography.primaryColor
    } else {
      familyColor = Typography.secondaryColor
    }
    modelNameLabel.attributedStringValue = Format.modelName(
      family: model.family,
      size: model.sizeLabel,
      familyColor: familyColor,
      sizeColor: familyColor
    )

    metadataLabel.attributedStringValue = Format.modelMetadata(for: model, color: familyColor)

    if let progress = modelManager.downloadProgress(for: model) {
      progressLabel.stringValue = Format.progressText(progress)
      cancelImageView.isHidden = false
      iconView.inactiveTintColor = Typography.tertiaryColor
    } else {
      progressLabel.stringValue = ""
      cancelImageView.isHidden = true
      iconView.inactiveTintColor = Typography.secondaryColor
    }

    // Delete button only for installed models on hover
    deleteImageView.isHidden = !modelManager.isInstalled(model) || !isHighlighted

    // Update icon state
    iconView.setLoading(isLoading)
    iconView.isActive = isActive

    needsDisplay = true
  }

  override func highlightDidChange(_ highlighted: Bool) {
    deleteImageView.isHidden = !modelManager.isInstalled(model) || !highlighted
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .systemRed
    deleteImageView.contentTintColor = .tertiaryLabelColor
  }

  @objc private func performDelete() {
    guard modelManager.isInstalled(model) else { return }
    modelManager.deleteDownloadedModel(model)
    membershipChanged(model)
  }
}
