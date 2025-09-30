import AppKit
import Foundation

private final class InstalledModelActionsView: NSView {
  private enum Action {
    case ellipsis
    case delete
    case reveal
    case stop
  }

  var onDelete: (() -> Void)?
  var onReveal: (() -> Void)?
  var onStop: (() -> Void)?

  private let ellipsisButton: NSButton
  private let ellipsisImageView: NSImageView
  private let deleteButton: NSButton
  private let deleteImageView: NSImageView
  private let revealButton: NSButton
  private let revealImageView: NSImageView
  private let stopButton: NSButton
  private let stopImageView: NSImageView

  private var isExpanded = false
  private var latestStatus: ModelStatus = .available
  private var latestIsRunning = false
  private var latestHighlight = false

  override init(frame frameRect: NSRect) {
    let ellipsis = Self.makeButton(
      symbolName: "ellipsis",
      accessibilityLabel: "More actions"
    )
    ellipsisButton = ellipsis.button
    ellipsisImageView = ellipsis.imageView

    let delete = Self.makeButton(
      symbolName: "trash",
      accessibilityLabel: "Delete model"
    )
    deleteButton = delete.button
    deleteImageView = delete.imageView

    let reveal = Self.makeButton(
      symbolName: "folder",
      accessibilityLabel: "Show in Finder"
    )
    revealButton = reveal.button
    revealImageView = reveal.imageView

    let stop = Self.makeButton(
      symbolName: "stop",
      accessibilityLabel: "Stop model",
      tint: .systemRed
    )
    stopButton = stop.button
    stopImageView = stop.imageView

    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = false

    ellipsisButton.target = self
    ellipsisButton.action = #selector(didTapEllipsis)
    deleteButton.target = self
    deleteButton.action = #selector(didTapDelete)
    revealButton.target = self
    revealButton.action = #selector(didTapReveal)
    stopButton.target = self
    stopButton.action = #selector(didTapStop)

    let stack = NSStackView(views: [ellipsisButton, stopButton, deleteButton, revealButton])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 6
    stack.detachesHiddenViews = true

    addSubview(stack)

    NSLayoutConstraint.activate([
      ellipsisButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      ellipsisButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      stopButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      stopButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      deleteButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      deleteButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      revealButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      revealButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),

      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    collapseActions()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(for status: ModelStatus, isRunning: Bool, highlighted: Bool) {
    latestStatus = status
    latestIsRunning = isRunning
    latestHighlight = highlighted

    switch status {
    case .available, .downloading:
      collapseActions()
      ellipsisButton.isHidden = true
      deleteButton.isHidden = true
      revealButton.isHidden = true
      stopButton.isHidden = true
    case .downloaded:
      if isRunning {
        collapseActions()
        ellipsisButton.isHidden = true
        deleteButton.isHidden = true
        revealButton.isHidden = true
        stopButton.isHidden = false
      } else if highlighted {
        ellipsisButton.isHidden = isExpanded
        deleteButton.isHidden = !isExpanded
        revealButton.isHidden = !isExpanded
        stopButton.isHidden = true
      } else {
        collapseActions()
        ellipsisButton.isHidden = true
        deleteButton.isHidden = true
        revealButton.isHidden = true
        stopButton.isHidden = true
      }
    }

    updateTints()
  }

  func collapseActions() {
    isExpanded = false
  }

  func isInteractiveArea(at parentPoint: NSPoint, in parentView: NSView) -> Bool {
    let localPoint = convert(parentPoint, from: parentView)
    guard bounds.contains(localPoint) else { return false }
    return hitTest(localPoint) != nil
  }

  private func handle(action: Action) {
    switch action {
    case .ellipsis:
      isExpanded.toggle()
      update(for: latestStatus, isRunning: latestIsRunning, highlighted: latestHighlight)
    case .delete: onDelete?()
    case .reveal: onReveal?()
    case .stop: onStop?()
    }
  }

  private func updateTints() {
    let tint = latestHighlight ? NSColor.labelColor : NSColor.secondaryLabelColor
    ellipsisImageView.contentTintColor = tint
    deleteImageView.contentTintColor = tint
    revealImageView.contentTintColor = tint
    stopImageView.contentTintColor = .systemRed
  }

  @objc private func didTapEllipsis() { handle(action: .ellipsis) }
  @objc private func didTapDelete() { handle(action: .delete) }
  @objc private func didTapReveal() { handle(action: .reveal) }
  @objc private func didTapStop() { handle(action: .stop) }

  private static func makeButton(
    symbolName: String,
    accessibilityLabel: String,
    tint: NSColor = .secondaryLabelColor
  ) -> (button: NSButton, imageView: NSImageView) {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.setButtonType(.momentaryChange)
    button.title = ""
    button.toolTip = accessibilityLabel
    button.setAccessibilityLabel(accessibilityLabel)

    let imageView = NSImageView()
    if let img = NSImage(
      systemSymbolName: symbolName,
      accessibilityDescription: accessibilityLabel
    ) {
      img.isTemplate = true
      imageView.image = img
    }
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    imageView.imageScaling = .scaleProportionallyDown
    imageView.contentTintColor = tint
    button.addSubview(imageView)

    NSLayoutConstraint.activate([
      imageView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      imageView.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      imageView.heightAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
    ])

    return (button, imageView)
  }
}

/// Menu row representing a single installed model.
/// Visual states:
/// - Idle: circular icon (inactive) + label
/// - Loading: circular icon (active)
/// - Running: circular icon (active)
final class InstalledModelMenuItemView: MenuRowView, NSGestureRecognizerDelegate {
  private let model: ModelCatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  private static let iconBaselineYOffset: CGFloat = -2

  // Subviews
  private let circleIcon = CircularIconView()
  private let labelField = NSTextField(labelWithString: "")
  private let progressLabel = NSTextField(labelWithString: "")
  // Second-line label: used for progress during downloads and for
  // consistent two-line layout (size/badges) when idle/running.
  private let infoRow = NSStackView()
  private let sizeLabel = NSTextField(labelWithString: "")
  private let separatorLabel = CenteredDotSeparatorView()
  private let ctxLabel = NSTextField(labelWithString: "")
  private let memorySeparatorLabel = CenteredDotSeparatorView()
  private let memoryLabel = NSTextField(labelWithString: "")
  private let cancelImageView = NSImageView()
  private let actionsView = InstalledModelActionsView()

  // Hover handling is provided by MenuRowView
  private var rowClickRecognizer: NSClickGestureRecognizer?

  init(
    model: ModelCatalogEntry, server: LlamaServer, modelManager: ModelManager,
    membershipChanged: @escaping () -> Void
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

    labelField.stringValue = model.displayName
    labelField.font = Typography.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false

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

    let labels = [sizeLabel, ctxLabel, memoryLabel]
    for label in labels {
      label.font = Typography.secondary
      label.textColor = .secondaryLabelColor
      label.lineBreakMode = .byTruncatingTail
      label.translatesAutoresizingMaskIntoConstraints = false
    }

    infoRow.orientation = .horizontal
    infoRow.spacing = 4
    infoRow.alignment = .centerY
    infoRow.translatesAutoresizingMaskIntoConstraints = false
    infoRow.addArrangedSubview(sizeLabel)
    infoRow.addArrangedSubview(memorySeparatorLabel)
    infoRow.addArrangedSubview(memoryLabel)
    infoRow.addArrangedSubview(separatorLabel)
    infoRow.addArrangedSubview(ctxLabel)

    actionsView.onDelete = { [weak self] in self?.performDelete() }
    actionsView.onReveal = { [weak self] in self?.performReveal() }
    actionsView.onStop = { [weak self] in self?.performStop() }

    // Order: icon | (label over bytes) | spacer | (state, progress, delete, action)
    // Spacer expands so trailing visuals sit flush right.
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    labelField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    labelField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    progressLabel.setContentHuggingPriority(.required, for: .horizontal)
    progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    // Left: icon aligned with first text line, then two-line text column
    let nameStack = NSStackView(views: [labelField, infoRow])
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

    let rightStack = NSStackView(views: [progressLabel, cancelImageView, actionsView])
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
      circleIcon.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      circleIcon.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      cancelImageView.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      cancelImageView.heightAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),

      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.progressWidth),
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

  // Row click recognizer to toggle, letting the delete button handle its own action.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if rowClickRecognizer == nil {
      let click = NSClickGestureRecognizer(target: self, action: #selector(didClickRow))
      click.delegate = self
      addGestureRecognizer(click)
      rowClickRecognizer = click
    }
  }

  @objc private func didClickRow() { toggle() }

  private func toggle() {
    let status = modelManager.getModelStatus(model)
    switch status {
    case .downloaded:
      if server.isActive(model: model) { server.stop() } else { server.start(model: model) }
    case .downloading:
      modelManager.cancelModelDownload(model)
      membershipChanged()
    case .available:
      break
    }
    refresh()
  }

  // Prevent row-level toggle when clicking inline action buttons.
  func gestureRecognizer(
    _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
  ) -> Bool {
    let location = convert(event.locationInWindow, from: nil)
    if actionsView.isInteractiveArea(at: location, in: self) { return false }
    return true
  }

  override func hoverHighlightDidChange(_ highlighted: Bool) {
    let status = modelManager.getModelStatus(model)
    actionsView.update(
      for: status,
      isRunning: server.isActive(model: model) && server.isRunning,
      highlighted: highlighted
    )
    // Update icon tint when highlight changes.
    applyIconTint()
  }

  func refresh() {
    // Determine state
    let status = modelManager.getModelStatus(model)
    let isActive = server.isActive(model: model)
    let isLoadingServer = isActive && server.isLoading
    let isRunning = isActive && server.isRunning
    let recommendedContext = ModelCatalog.recommendedContextLength(for: model)
    // Reset trailing visuals before applying current status
    cancelImageView.isHidden = true

    // Spinner is now displayed inside the circular icon instead of the right side.
    circleIcon.setLoading(isLoadingServer)

    let sizeText = model.totalSize
    let contextText: String = {
      if let recommendedContext {
        return TokenFormatters.shortTokens(recommendedContext)
      }
      return ""
    }()
    let memoryText: String? = {
      if isRunning {
        let memMB = server.memoryUsageMB
        if memMB <= 0 { return nil }
        if memMB >= 1024 {
          let gb = memMB / 1024
          let gbText = gb < 10 ? String(format: "%.1f", gb) : String(format: "%.0f", gb)
          return "\(gbText) GB"
        } else {
          return String(format: "%.0f MB", memMB)
        }
      }
      return nil
    }()

    // Download progress / action area
    switch status {
    case .downloading(let progress):
      cancelImageView.isHidden = false
      let percent: Int
      if progress.totalUnitCount > 0 {
        percent = Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
      } else {
        percent = 0
      }
      progressLabel.stringValue = "\(percent)%"
      // Second line: always show downloaded/total in GB with two decimals.
      // When the network hasn't reported a total yet (0), fall back to catalog size.
      let completedText = ByteFormatters.gbTwoDecimals(progress.completedUnitCount)
      let totalBytes: Int64 = {
        if progress.totalUnitCount > 0 {
          return progress.totalUnitCount
        } else {
          // fileSize is our catalog estimate for the full model (all parts).
          return model.fileSize
        }
      }()
      let totalText = ByteFormatters.gbTwoDecimals(totalBytes)
      sizeLabel.attributedStringValue = IconLabelFormatter.make(
        icon: IconLabelFormatter.sizeSymbol,
        text: "\(completedText) / \(totalText)",
        color: .secondaryLabelColor,
        baselineOffset: Self.iconBaselineYOffset
      )
      ctxLabel.stringValue = ""
      ctxLabel.isHidden = true
      memoryLabel.stringValue = ""
      memoryLabel.isHidden = true
      memorySeparatorLabel.isHidden = true
      separatorLabel.isHidden = true
      infoRow.isHidden = false
      // Removed indicator image in favor of simplified state display
      actionsView.update(
        for: .downloading(progress),
        isRunning: isRunning,
        highlighted: isHoverHighlighted
      )
    case .downloaded, .available:
      progressLabel.stringValue = ""
      infoRow.isHidden = false

      sizeLabel.attributedStringValue = IconLabelFormatter.make(
        icon: IconLabelFormatter.sizeSymbol,
        text: sizeText,
        color: .secondaryLabelColor,
        baselineOffset: Self.iconBaselineYOffset
      )
      if contextText.isEmpty {
        ctxLabel.isHidden = true
        separatorLabel.isHidden = true
      } else {
        ctxLabel.attributedStringValue = IconLabelFormatter.make(
          icon: IconLabelFormatter.contextSymbol,
          text: contextText,
          color: .secondaryLabelColor,
          baselineOffset: Self.iconBaselineYOffset
        )
        ctxLabel.isHidden = false
        separatorLabel.isHidden = false
      }

      if let memoryText {
        memoryLabel.attributedStringValue = IconLabelFormatter.make(
          icon: IconLabelFormatter.memorySymbol,
          text: memoryText,
          color: .secondaryLabelColor,
          baselineOffset: Self.iconBaselineYOffset
        )
        memoryLabel.isHidden = false
        memorySeparatorLabel.isHidden = false
      } else {
        memoryLabel.stringValue = ""
        memoryLabel.isHidden = true
        memorySeparatorLabel.isHidden = true
      }

      actionsView.update(
        for: status,
        isRunning: isRunning,
        highlighted: isHoverHighlighted
      )
    }
    // Update leading circular badge state and tinting
    // Icon should become blue only after the model is done loading (running)
    circleIcon.isActive = isRunning
    applyIconTint(isActive: isRunning)
    needsDisplay = true
  }

  /// Installed model icons use the primary label tint unless the server is running,
  /// in which case the circular badge handles the white active glyph.
  private func applyIconTint(isActive: Bool? = nil) {
    let statusIsActive: Bool
    if let isActive = isActive {
      statusIsActive = isActive
    } else {
      let isActiveModel = server.isActive(model: model)
      // Consider active (blue) only when the server is running
      statusIsActive = isActiveModel && server.isRunning
    }
    // When active, circular view sets white tint; only tweak in inactive state.
    if !statusIsActive {
      circleIcon.imageView.contentTintColor = .labelColor
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .systemRed
    let status = modelManager.getModelStatus(model)
    actionsView.update(
      for: status,
      isRunning: server.isActive(model: model) && server.isRunning,
      highlighted: isHoverHighlighted
    )
  }

  private func performDelete() {
    let status = modelManager.getModelStatus(model)
    guard case .downloaded = status else { return }
    modelManager.deleteDownloadedModel(model)
    membershipChanged()
  }

  private func performStop() {
    let isActive = server.isActive(model: model)
    guard isActive else { return }
    server.stop()
    refresh()
  }

  private func performReveal() {
    let url = URL(fileURLWithPath: model.modelFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

}
