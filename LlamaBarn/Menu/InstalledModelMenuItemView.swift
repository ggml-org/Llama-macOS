import AppKit
import Foundation

/// Menu row representing a single installed model.
/// Visual states:
/// - Idle: circular icon (inactive) + label
/// - Loading: circular icon (active)
/// - Running: circular icon (active)
final class InstalledModelMenuItemView: MenuRowView, NSGestureRecognizerDelegate {
  private let model: CatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: Manager
  private let membershipChanged: (CatalogEntry) -> Void

  private static let iconBaselineYOffset: CGFloat = -2

  // Subviews
  private let circleIcon = CircularIconView()
  private let modelNameLabel = NSTextField(labelWithString: "")
  private let metadataLabel = NSTextField(labelWithString: "")
  private let progressLabel = NSTextField(labelWithString: "")
  private let cancelImageView = NSImageView()
  private let deleteImageView = NSImageView()

  // Hover handling is provided by MenuRowView
  private var rowClickRecognizer: NSClickGestureRecognizer?
  private var deleteClickRecognizer: NSClickGestureRecognizer?

  init(
    model: CatalogEntry, server: LlamaServer, modelManager: Manager,
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

    modelNameLabel.stringValue = model.displayName
    modelNameLabel.font = Typography.primary
    modelNameLabel.lineBreakMode = .byTruncatingTail
    modelNameLabel.translatesAutoresizingMaskIntoConstraints = false

    metadataLabel.font = Typography.secondary
    metadataLabel.textColor = .secondaryLabelColor
    metadataLabel.lineBreakMode = .byTruncatingTail
    metadataLabel.translatesAutoresizingMaskIntoConstraints = false

    progressLabel.font = Typography.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel download") {
      img.isTemplate = true
      cancelImageView.image = img
    }
    cancelImageView.translatesAutoresizingMaskIntoConstraints = false
    cancelImageView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    cancelImageView.imageScaling = .scaleProportionallyDown
    cancelImageView.contentTintColor = .systemRed
    cancelImageView.isHidden = true

    deleteImageView.translatesAutoresizingMaskIntoConstraints = false
    deleteImageView.imageScaling = .scaleProportionallyDown
    deleteImageView.symbolConfiguration = .init(pointSize: 13, weight: .regular)
    if let img = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete") {
      img.isTemplate = true
      deleteImageView.image = img
    }
    deleteImageView.contentTintColor = .secondaryLabelColor
    deleteImageView.isHidden = true

    // Spacer expands so trailing visuals sit flush right.
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    modelNameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    modelNameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    progressLabel.setContentHuggingPriority(.required, for: .horizontal)
    progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    // Left: icon aligned with first text line, then two-line text column
    let nameStack = NSStackView(views: [modelNameLabel, metadataLabel])
    nameStack.translatesAutoresizingMaskIntoConstraints = false
    nameStack.orientation = .vertical
    nameStack.spacing = 1
    nameStack.alignment = .leading

    let leading = NSStackView(views: [circleIcon, nameStack])
    leading.translatesAutoresizingMaskIntoConstraints = false
    leading.orientation = .horizontal
    // Vertically center the circular icon relative to the two-line text, like Wi‑Fi menu
    leading.alignment = .centerY
    leading.spacing = 6

    // Right: status/progress/delete/action in a row
    cancelImageView.setContentHuggingPriority(.required, for: .horizontal)
    cancelImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

    let rightStack = NSStackView(views: [progressLabel, cancelImageView, deleteImageView])
    rightStack.translatesAutoresizingMaskIntoConstraints = false
    rightStack.orientation = .horizontal
    rightStack.spacing = 6
    rightStack.alignment = .centerY

    let rootStack = NSStackView(views: [leading, spacer, rightStack])
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    rootStack.orientation = .horizontal
    rootStack.spacing = 6
    rootStack.alignment = .centerY
    contentView.addSubview(rootStack)

    NSLayoutConstraint.activate([
      circleIcon.widthAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      circleIcon.heightAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      cancelImageView.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.iconSize),
      cancelImageView.heightAnchor.constraint(lessThanOrEqualToConstant: Metrics.iconSize),
      deleteImageView.widthAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      deleteImageView.heightAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),

      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.progressWidth),
      rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      // Pin trailing controls to the backgroundView’s edge (hover highlight),
      // not the contentView’s inner padding, so the trash icon visually
      // reaches the end of the item.
      // Respect the item’s standard inner padding so the trash aligns
      // consistently with other rows.
      rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  // Row click recognizer to toggle, letting the delete icon handle its own action.
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

  // Prevent row toggle when clicking the delete icon.
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
    let status = modelManager.getModelStatus(model)
    switch status {
    case .downloaded:
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
    let status = modelManager.getModelStatus(model)
    deleteImageView.isHidden = !(highlighted && status == .downloaded)
  }

  func refresh() {
    let status = modelManager.getModelStatus(model)
    let isActive = server.isActive(model: model)
    let isServerLoading = isActive && server.isLoading
    let isRunning = isActive && server.isRunning

    // Update icon state
    circleIcon.setLoading(isServerLoading)
    circleIcon.isActive = isRunning
    circleIcon.imageView.contentTintColor = isRunning ? .white : .labelColor

    // Build info text based on state
    switch status {
    case .downloading(let progress):
      cancelImageView.isHidden = false
      let percent =
        progress.totalUnitCount > 0
        ? Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
        : 0
      progressLabel.stringValue = "\(percent)%"

      let completedSizeText = ByteFormatters.gbTwoDecimals(progress.completedUnitCount)
      let totalBytes = progress.totalUnitCount > 0 ? progress.totalUnitCount : model.fileSize
      let totalSizeText = ByteFormatters.gbTwoDecimals(totalBytes)

      metadataLabel.attributedStringValue = IconLabelFormatter.make(
        icon: IconLabelFormatter.sizeSymbol,
        text: "\(completedSizeText) / \(totalSizeText)",
        color: .secondaryLabelColor,
        baselineOffset: Self.iconBaselineYOffset
      )

    case .downloaded, .available:
      cancelImageView.isHidden = true
      progressLabel.stringValue = ""
      metadataLabel.attributedStringValue = buildInfoText(isRunning: isRunning)
    }

    needsDisplay = true
  }

  /// Build the info line with size, context, and optionally memory usage.
  private func buildInfoText(isRunning: Bool) -> NSAttributedString {
    let result = NSMutableAttributedString()

    // Always show size
    result.append(
      IconLabelFormatter.make(
        icon: IconLabelFormatter.sizeSymbol,
        text: model.totalSize,
        color: .secondaryLabelColor,
        baselineOffset: Self.iconBaselineYOffset
      ))

    // Add context if available
    if let recommendedContext = Catalog.recommendedContextLength(for: model) {
      result.append(makeSeparator())
      result.append(
        IconLabelFormatter.make(
          icon: IconLabelFormatter.contextSymbol,
          text: TokenFormatters.shortTokens(recommendedContext),
          color: .secondaryLabelColor,
          baselineOffset: Self.iconBaselineYOffset
        ))
    }

    // Add memory usage when running
    if isRunning {
      let memMB = server.memoryUsageMB
      if memMB > 0 {
        let memoryText: String
        if memMB >= 1024 {
          let gb = memMB / 1024
          memoryText = gb < 10 ? String(format: "%.1f GB", gb) : String(format: "%.0f GB", gb)
        } else {
          memoryText = String(format: "%.0f MB", memMB)
        }
        result.append(makeSeparator())
        result.append(
          IconLabelFormatter.make(
            icon: IconLabelFormatter.memorySymbol,
            text: memoryText,
            color: .secondaryLabelColor,
            baselineOffset: Self.iconBaselineYOffset
          ))
      }
    }

    return result
  }

  /// Create a centered dot separator for the info line.
  private func makeSeparator() -> NSAttributedString {
    MetadataSeparator.make()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .systemRed
    deleteImageView.contentTintColor = .secondaryLabelColor
  }

  @objc private func performDelete() {
    let status = modelManager.getModelStatus(model)
    guard case .downloaded = status else { return }
    modelManager.deleteDownloadedModel(model)
    membershipChanged(model)
  }

}
