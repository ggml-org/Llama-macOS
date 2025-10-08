import AppKit
import Foundation

/// Interactive menu item representing a single installed model.
/// Visual states:
/// - Idle: circular icon (inactive) + label
/// - Loading: circular icon (active)
/// - Running: circular icon (active)
final class InstalledModelItemView: ItemView, NSGestureRecognizerDelegate {
  private let model: CatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let membershipChanged: (CatalogEntry) -> Void

  // Subviews
  private let circleIcon = IconBadgeView()
  private let modelNameLabel = Typography.makePrimaryLabel()
  private let metadataLabel = Typography.makeSecondaryLabel()
  private let progressLabel = Typography.makeSecondaryLabel()
  private let cancelImageView = NSImageView()
  private let deleteLabel = Typography.makeSecondaryLabel("delete")

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

  override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 40) }

  private func setup() {
    wantsLayer = true
    circleIcon.setImage(NSImage(named: model.icon))

    progressLabel.alignment = .right

    // Configure cancel button
    if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil) {
      img.isTemplate = true
      cancelImageView.image = img
    }
    cancelImageView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    cancelImageView.contentTintColor = .systemRed
    cancelImageView.isHidden = true

    deleteLabel.textColor = Typography.secondaryColor
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
    nameStack.spacing = 1
    nameStack.alignment = .leading

    let leading = NSStackView(views: [circleIcon, nameStack])
    leading.orientation = .horizontal
    // Vertically center the circular icon relative to the two-line text, like Wi‑Fi menu
    leading.alignment = .centerY
    leading.spacing = 6

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
      circleIcon.widthAnchor.constraint(equalToConstant: Layout.iconBadgeSize),
      circleIcon.heightAnchor.constraint(equalToConstant: Layout.iconBadgeSize),
      cancelImageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.iconSize),
      cancelImageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.iconSize),

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
    let status = modelManager.status(for: model)
    switch status {
    case .installed:
      if server.isActive(model: model) { server.stop() } else { server.start(model: model) }
    case .downloading:
      modelManager.cancelModelDownload(model)
      membershipChanged(model)
    case .available:
      break
    }
    refresh()
  }

  override func hoverHighlightDidChange(_ highlighted: Bool) {
    let status = modelManager.status(for: model)
    deleteLabel.isHidden = !(highlighted && status == .installed)
  }

  func refresh() {
    let status = modelManager.status(for: model)
    let isActive = server.isActive(model: model)
    let isLoading = isActive && server.isLoading
    let isDownloading = if case .downloading = status { true } else { false }

    // Compute colors once
    let itemColor = isDownloading ? Typography.secondaryColor : Typography.primaryColor
    let titleColor = isDownloading ? Typography.secondaryColor : .controlTextColor

    // Apply values directly
    modelNameLabel.stringValue = model.menuTitle
    modelNameLabel.textColor = titleColor
    metadataLabel.attributedStringValue = ModelMetadataFormatters.makeMetadataText(for: model)

    // Progress and cancel button only for downloading
    if case .downloading(let progress) = status {
      progressLabel.stringValue = ProgressFormatters.percentText(progress)
      cancelImageView.isHidden = false
    } else {
      progressLabel.stringValue = ""
      cancelImageView.isHidden = true
    }

    // Update icon state
    circleIcon.setLoading(isLoading)
    circleIcon.isActive = isActive
    circleIcon.inactiveTintColor = itemColor

    needsDisplay = true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .systemRed
    deleteLabel.textColor = Typography.secondaryColor
  }

  @objc private func performDelete() {
    let status = modelManager.status(for: model)
    guard case .installed = status else { return }
    modelManager.deleteDownloadedModel(model)
    membershipChanged(model)
  }
}
