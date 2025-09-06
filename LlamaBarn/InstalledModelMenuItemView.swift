import AppKit
import Foundation

/// Menu row representing a single installed model.
/// Visual states:
/// - Idle: circular icon (inactive) + label
/// - Loading: circular icon (active) + spinner
/// - Running: circular icon (active)
final class InstalledModelMenuItemView: MenuRowView, NSGestureRecognizerDelegate {
  private let model: ModelCatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  // Subviews
  private let circleIcon = CircularIconView()
  private let labelField = NSTextField(labelWithString: "")
  private let stateContainer = NSView()
  private let spinner = NSProgressIndicator()
  private let indicatorImageView = NSImageView()
  private let progressLabel = NSTextField(labelWithString: "")
  // Second-line label: used for progress during downloads and for
  // consistent two-line layout (size/badges) when idle/running.
  private let bytesLabel = NSTextField(labelWithString: "")
  // Trailing action controls
  private let ellipsisContainer = NSView()
  private let ellipsisButton = NSButton()
  private let deleteButton = NSButton()
  private let revealButton = NSButton()
  private var actionsExpanded = false
  // No per-ellipsis hover state; keep things simple

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
    labelField.font = MenuTypography.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.isDisplayedWhenStopped = false

    indicatorImageView.translatesAutoresizingMaskIntoConstraints = false
    indicatorImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    indicatorImageView.contentTintColor = .controlAccentColor
    indicatorImageView.isHidden = true

    progressLabel.font = MenuTypography.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    bytesLabel.font = MenuTypography.secondary
    bytesLabel.textColor = .secondaryLabelColor
    bytesLabel.alignment = .left
    bytesLabel.translatesAutoresizingMaskIntoConstraints = false
    bytesLabel.isHidden = false

    // Ellipsis shows on hover; on click it expands to inline actions
    ellipsisContainer.translatesAutoresizingMaskIntoConstraints = false
    ellipsisContainer.wantsLayer = false

    ellipsisButton.translatesAutoresizingMaskIntoConstraints = false
    ellipsisButton.isBordered = false
    ellipsisButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More actions")
    ellipsisButton.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    ellipsisButton.contentTintColor = .tertiaryLabelColor
    ellipsisButton.target = self
    ellipsisButton.action = #selector(toggleActions)
    ellipsisButton.toolTip = "More actions"
    ellipsisButton.isHidden = true
    ellipsisContainer.addSubview(ellipsisButton)

    deleteButton.translatesAutoresizingMaskIntoConstraints = false
    deleteButton.isBordered = false
    deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete model")
    deleteButton.contentTintColor = .tertiaryLabelColor
    deleteButton.target = self
    deleteButton.action = #selector(handleDelete)
    deleteButton.toolTip = "Delete model"
    deleteButton.isHidden = true

    revealButton.translatesAutoresizingMaskIntoConstraints = false
    revealButton.isBordered = false
    revealButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Show in Finder")
    revealButton.contentTintColor = .tertiaryLabelColor
    revealButton.target = self
    revealButton.action = #selector(handleRevealInFinder)
    revealButton.toolTip = "Show in Finder"
    revealButton.isHidden = true

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
    let nameStack = NSStackView(views: [labelField, bytesLabel])
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
    let rightStack = NSStackView(views: [stateContainer, progressLabel, ellipsisContainer, revealButton, deleteButton, indicatorImageView])
    rightStack.translatesAutoresizingMaskIntoConstraints = false
    rightStack.orientation = .horizontal
    rightStack.spacing = 6
    rightStack.alignment = .centerY
    // Hidden arranged subviews should be fully detached from layout so they
    // don't reserve space when not visible (e.g., the legacy play/stop slot).
    rightStack.detachesHiddenViews = true

    let rootStack = NSStackView(views: [leading, spacer, rightStack])
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    rootStack.orientation = .horizontal
    rootStack.spacing = 6
    rootStack.alignment = .centerY
    contentView.addSubview(rootStack)

    NSLayoutConstraint.activate([
      circleIcon.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      circleIcon.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      stateContainer.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      stateContainer.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      indicatorImageView.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      indicatorImageView.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      // Make the ellipsis hit target slightly larger while keeping the glyph aligned
      ellipsisContainer.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize + 8),
      ellipsisContainer.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize + 6),
      ellipsisButton.centerXAnchor.constraint(equalTo: ellipsisContainer.centerXAnchor),
      ellipsisButton.centerYAnchor.constraint(equalTo: ellipsisContainer.centerYAnchor),
      ellipsisButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      ellipsisButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      deleteButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      deleteButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      revealButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      revealButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
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

  private func setEllipsisVisible(_ visible: Bool) {
    ellipsisContainer.isHidden = !visible
    ellipsisButton.isHidden = !visible
  }

  // Prevent row-level toggle when clicking inline action buttons.
  func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
    let location = convert(event.locationInWindow, from: nil)
    // If click is inside any of the action buttons, let the button handle it.
    let actionViews: [NSView] = [ellipsisContainer, ellipsisButton, revealButton, deleteButton]
    for v in actionViews where !v.isHidden {
      let frame = v.convert(v.bounds, to: self)
      if frame.contains(location) { return false }
    }
    return true
  }

  override func hoverHighlightDidChange(_ highlighted: Bool) {
    let status = modelManager.getModelStatus(model)
    updateActionsVisibility(for: status, highlighted: highlighted)
    // Update icon tint when highlight changes.
    applyIconTint()
    applyActionTints()
  }

  func refresh() {
    // Determine state
    let status = modelManager.getModelStatus(model)
    let isActive = server.isActive(model: model)
    let isLoadingServer = isActive && server.isLoading
    let isRunning = isActive && server.isRunning

    // Clear state container
    stateContainer.subviews.forEach { $0.removeFromSuperview() }
    spinner.stopAnimation(nil)

    if isLoadingServer {
      stateContainer.addSubview(spinner)
      NSLayoutConstraint.activate([
        spinner.centerXAnchor.constraint(equalTo: stateContainer.centerXAnchor),
        spinner.centerYAnchor.constraint(equalTo: stateContainer.centerYAnchor),
      ])
      spinner.startAnimation(nil)
    }
    // Compose a default secondary line (size + capability badges) used when not downloading
    let defaultSecondary: String = model.totalSize

    // Download progress / action area
    switch status {
    case .downloading(let progress):
      let percent: Int
      if progress.totalUnitCount > 0 {
        percent = Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
      } else {
        percent = 0
      }
      progressLabel.stringValue = "\(percent)%"
      // Second line: show downloaded/total in GB with two decimals
      let completedText = ByteFormatters.gbTwoDecimals(progress.completedUnitCount)
      if progress.totalUnitCount > 0 {
        let totalText = ByteFormatters.gbTwoDecimals(progress.totalUnitCount)
        bytesLabel.stringValue = "\(completedText) / \(totalText)"
      } else {
        bytesLabel.stringValue = completedText
      }
      bytesLabel.isHidden = false
      indicatorImageView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
      indicatorImageView.contentTintColor = .systemRed
      indicatorImageView.isHidden = false
      updateActionsVisibility(for: .downloading(progress), highlighted: isHoverHighlighted)
    case .downloaded:
      // Memory usage now lives in the header; keep the right side empty when not downloading.
      progressLabel.stringValue = ""
      bytesLabel.stringValue = defaultSecondary
      bytesLabel.isHidden = false
      // No play/stop affordance; active state is conveyed by circular icon.
      indicatorImageView.image = nil
      indicatorImageView.isHidden = true
      updateActionsVisibility(for: .downloaded, highlighted: isHoverHighlighted)
    case .available:
      progressLabel.stringValue = ""
      bytesLabel.stringValue = defaultSecondary
      bytesLabel.isHidden = false
      indicatorImageView.image = nil
      indicatorImageView.isHidden = true
      updateActionsVisibility(for: .available, highlighted: isHoverHighlighted)
    }
    // Update leading circular badge state and tinting
    // Icon should become blue only after the model is done loading (running)
    circleIcon.isActive = isRunning
    applyIconTint(isActive: isRunning)
    applyActionTints()
    needsDisplay = true
  }

  /// Centralizes which trailing actions are visible based on status + hover state.
  private func updateActionsVisibility(for status: ModelStatus, highlighted: Bool) {
    switch status {
    case .downloading:
      actionsExpanded = false
      setEllipsisVisible(false)
      revealButton.isHidden = true
      deleteButton.isHidden = true
    case .available:
      actionsExpanded = false
      setEllipsisVisible(false)
      revealButton.isHidden = true
      deleteButton.isHidden = true
    case .downloaded:
      if highlighted {
        setEllipsisVisible(!actionsExpanded)
        revealButton.isHidden = !actionsExpanded
        deleteButton.isHidden = !actionsExpanded
      } else {
        actionsExpanded = false
        setEllipsisVisible(false)
        revealButton.isHidden = true
        deleteButton.isHidden = true
      }
    }
  }

  /// Adjusts the icon tint to reduce excessive contrast of colorful brand logos vs text labels.
  /// Idle/normal: secondary label color so text (primary) leads.
  /// Active (loading/running) or highlighted: primary label color for emphasis.
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
      circleIcon.imageView.contentTintColor = isHoverHighlighted ? .labelColor : .secondaryLabelColor
    }
  }

  // Neutral adaptive tint for action symbols; avoid strong destructive red by default.
  private func applyActionTints() {
    let buttons = [revealButton, deleteButton].filter { !$0.isHidden }
    guard !buttons.isEmpty else { return }
    let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    let hoverTint: NSColor = increaseContrast ? .labelColor : .secondaryLabelColor
    let idleTint: NSColor = increaseContrast ? .secondaryLabelColor : .tertiaryLabelColor
    let tint = isHoverHighlighted ? hoverTint : idleTint
    buttons.forEach { $0.contentTintColor = tint }
    // Keep ellipsis same tinting rules as other action buttons
    if !ellipsisContainer.isHidden { ellipsisButton.contentTintColor = tint }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyActionTints()
  }

  // No special tracking for the ellipsis area; the row keeps highlight itself.

  @objc private func toggleActions() {
    actionsExpanded.toggle()
    // Re-evaluate hover state to flip the visible controls accordingly
    hoverHighlightDidChange(isHoverHighlighted)
  }

  @objc private func handleDelete() {
    let status = modelManager.getModelStatus(model)
    guard case .downloaded = status else { return }
    modelManager.deleteDownloadedModel(model)
    membershipChanged()
  }

  @objc private func handleRevealInFinder() {
    let url = URL(fileURLWithPath: model.modelFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
