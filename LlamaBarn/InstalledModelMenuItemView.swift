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
  // Legacy right-side spinner no longer used for server loading; keep for layout compatibility.
  private let spinner = NSProgressIndicator()
  // Legacy indicator removed; use spinner inside circular icon instead.
  private let progressLabel = NSTextField(labelWithString: "")
  // Second-line label: used for progress during downloads and for
  // consistent two-line layout (size/badges) when idle/running.
  private let bytesLabel = NSTextField(labelWithString: "")
  // Trailing action controls
  private let ellipsisContainer = NSView()
  private let ellipsisButton = NSButton()
  private let ellipsisImageView = NSImageView()
  private let deleteButton = NSButton()
  private let stopButton = NSButton()
  private let deleteImageView = NSImageView()
  private let revealButton = NSButton()
  private let revealImageView = NSImageView()
  private let maxContextButton = NSButton()
  private let maxContextImageView = NSImageView()
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

    // indicatorImageView removed

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
    ellipsisButton.imagePosition = .imageOnly
    ellipsisButton.setButtonType(.momentaryChange)
    // Render symbol via imageView to avoid NSButton coloring quirks in dark/vibrant menus
    if let img = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More actions") {
      img.isTemplate = true
      ellipsisImageView.image = img
    }
    ellipsisImageView.translatesAutoresizingMaskIntoConstraints = false
    ellipsisImageView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    ellipsisImageView.imageScaling = .scaleProportionallyDown
    ellipsisImageView.contentTintColor = .secondaryLabelColor
    ellipsisButton.title = ""
    ellipsisButton.alternateTitle = ""
    ellipsisButton.attributedTitle = NSAttributedString(string: "")
    ellipsisButton.target = self
    ellipsisButton.action = #selector(toggleActions)
    ellipsisButton.toolTip = "More actions"
    ellipsisButton.isHidden = true
    // Avoid AppKit dimming/removing templated image on mouse down
    (ellipsisButton.cell as? NSButtonCell)?.highlightsBy = []
    ellipsisContainer.addSubview(ellipsisButton)
    ellipsisButton.addSubview(ellipsisImageView)
    ellipsisButton.setAccessibilityLabel("More actions")

    deleteButton.translatesAutoresizingMaskIntoConstraints = false
    deleteButton.isBordered = false
    deleteButton.imagePosition = .imageOnly
    deleteButton.setButtonType(.momentaryChange)
    if let img = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete model") {
      img.isTemplate = true
      deleteImageView.image = img
    }
    deleteImageView.translatesAutoresizingMaskIntoConstraints = false
    deleteImageView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    deleteImageView.imageScaling = .scaleProportionallyDown
    deleteImageView.contentTintColor = .secondaryLabelColor
    deleteButton.title = ""
    deleteButton.alternateTitle = ""
    deleteButton.attributedTitle = NSAttributedString(string: "")
    deleteButton.target = self
    deleteButton.action = #selector(handleDelete)
    deleteButton.toolTip = "Delete model"
    deleteButton.isHidden = true
    // Avoid AppKit dimming/removing templated image on mouse down
    (deleteButton.cell as? NSButtonCell)?.highlightsBy = []
    deleteButton.addSubview(deleteImageView)
    deleteButton.setAccessibilityLabel("Delete model")

    // Stop button (shown when this model is running)
    stopButton.translatesAutoresizingMaskIntoConstraints = false
    stopButton.isBordered = false
    stopButton.imagePosition = .imageOnly
    stopButton.setButtonType(.momentaryChange)
    if let img = NSImage(systemSymbolName: "stop", accessibilityDescription: "Stop model") {
      img.isTemplate = true
      // Use a thin configuration similar to other trailing icons
      let imageView = NSImageView()
      imageView.translatesAutoresizingMaskIntoConstraints = false
      imageView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
      imageView.imageScaling = .scaleProportionallyDown
      // Default to red tint; emphasize to full label contrast on hover
      imageView.contentTintColor = .systemRed
      imageView.image = img
      stopButton.addSubview(imageView)
      // Constrain inner image
      NSLayoutConstraint.activate([
        imageView.centerXAnchor.constraint(equalTo: stopButton.centerXAnchor),
        imageView.centerYAnchor.constraint(equalTo: stopButton.centerYAnchor),
        imageView.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
        imageView.heightAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      ])
    }
    stopButton.title = ""
    stopButton.alternateTitle = ""
    stopButton.attributedTitle = NSAttributedString(string: "")
    stopButton.target = self
    stopButton.action = #selector(handleStop)
    stopButton.toolTip = "Stop"
    stopButton.isHidden = true
    (stopButton.cell as? NSButtonCell)?.highlightsBy = []
    stopButton.setAccessibilityLabel("Stop model")

    revealButton.translatesAutoresizingMaskIntoConstraints = false
    revealButton.isBordered = false
    revealButton.imagePosition = .imageOnly
    revealButton.setButtonType(.momentaryChange)
    if let img = NSImage(systemSymbolName: "folder", accessibilityDescription: "Show in Finder") {
      img.isTemplate = true
      revealImageView.image = img
    }
    revealImageView.translatesAutoresizingMaskIntoConstraints = false
    revealImageView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    revealImageView.imageScaling = .scaleProportionallyDown
    revealImageView.contentTintColor = .secondaryLabelColor
    revealButton.title = ""
    revealButton.alternateTitle = ""
    revealButton.attributedTitle = NSAttributedString(string: "")
    revealButton.target = self
    revealButton.action = #selector(handleRevealInFinder)
    revealButton.toolTip = "Show in Finder"
    revealButton.isHidden = true
    // Avoid AppKit dimming/removing templated image on mouse down
    (revealButton.cell as? NSButtonCell)?.highlightsBy = []
    revealButton.addSubview(revealImageView)
    revealButton.setAccessibilityLabel("Show in Finder")

    maxContextButton.translatesAutoresizingMaskIntoConstraints = false
    maxContextButton.isBordered = false
    maxContextButton.imagePosition = .imageOnly
    maxContextButton.setButtonType(.momentaryChange)
    if let img = NSImage(systemSymbolName: "gauge.with.dots.needle.100percent", accessibilityDescription: "Run at Max Context") {
      img.isTemplate = true
      maxContextImageView.image = img
    }
    maxContextImageView.translatesAutoresizingMaskIntoConstraints = false
    maxContextImageView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    maxContextImageView.imageScaling = .scaleProportionallyDown
    maxContextImageView.contentTintColor = .secondaryLabelColor
    maxContextButton.title = ""
    maxContextButton.alternateTitle = ""
    maxContextButton.attributedTitle = NSAttributedString(string: "")
    maxContextButton.target = self
    maxContextButton.action = #selector(handleRunAtMaxContext)
    maxContextButton.toolTip = "Run at Max Context"
    maxContextButton.isHidden = true
    // Avoid AppKit dimming/removing templated image on mouse down
    (maxContextButton.cell as? NSButtonCell)?.highlightsBy = []
    maxContextButton.addSubview(maxContextImageView)
    maxContextButton.setAccessibilityLabel("Run at Max Context")

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
    let rightStack = NSStackView(views: [
      stateContainer, progressLabel, ellipsisContainer, stopButton, deleteButton, revealButton, maxContextButton,
    ])
    rightStack.translatesAutoresizingMaskIntoConstraints = false
    rightStack.orientation = .horizontal
    rightStack.spacing = 6
    rightStack.alignment = .centerY
    // Hidden arranged subviews should be fully detached from layout so they
    // don't reserve space when not visible (e.g., the legacy play/stop slot).
    rightStack.detachesHiddenViews = true
    // Remove the gap between the two action buttons when expanded
    rightStack.setCustomSpacing(0, after: deleteButton)
    rightStack.setCustomSpacing(0, after: revealButton)

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

      // Make the ellipsis hit target comfortably large and let the button fill it
      ellipsisContainer.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      ellipsisContainer.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      ellipsisButton.leadingAnchor.constraint(equalTo: ellipsisContainer.leadingAnchor),
      ellipsisButton.trailingAnchor.constraint(equalTo: ellipsisContainer.trailingAnchor),
      ellipsisButton.topAnchor.constraint(equalTo: ellipsisContainer.topAnchor),
      ellipsisButton.bottomAnchor.constraint(equalTo: ellipsisContainer.bottomAnchor),
      ellipsisImageView.centerXAnchor.constraint(equalTo: ellipsisButton.centerXAnchor),
      ellipsisImageView.centerYAnchor.constraint(equalTo: ellipsisButton.centerYAnchor),
      ellipsisImageView.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      ellipsisImageView.heightAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      stopButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      stopButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      deleteButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      deleteButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      deleteImageView.centerXAnchor.constraint(equalTo: deleteButton.centerXAnchor),
      deleteImageView.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
      deleteImageView.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      deleteImageView.heightAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      revealButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      revealButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      revealImageView.centerXAnchor.constraint(equalTo: revealButton.centerXAnchor),
      revealImageView.centerYAnchor.constraint(equalTo: revealButton.centerYAnchor),
      revealImageView.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      revealImageView.heightAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      maxContextButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      maxContextButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      maxContextImageView.centerXAnchor.constraint(equalTo: maxContextButton.centerXAnchor),
      maxContextImageView.centerYAnchor.constraint(equalTo: maxContextButton.centerYAnchor),
      maxContextImageView.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      maxContextImageView.heightAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
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
  func gestureRecognizer(
    _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
  ) -> Bool {
    let location = convert(event.locationInWindow, from: nil)
    // If click is inside any of the action buttons, let the button handle it.
    let actionViews: [NSView] = [ellipsisContainer, ellipsisButton, stopButton, revealButton, deleteButton, maxContextButton]
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

    // Spinner is now displayed inside the circular icon instead of the right side.
    circleIcon.setLoading(isLoadingServer)
    // Compose a default secondary line (size + capability badges) used when not downloading
    let runningContext: String? = {
      guard isRunning, let ctx = server.activeContextLength else { return nil }
      let ctxLabel = TokenFormatters.shortTokens(ctx)
      return "Ctx \(ctxLabel)"
    }()
    let defaultSecondary: String = {
      if let runningContext {
        // When running, show context and live memory usage on line 2.
        let memMB = server.memoryUsageMB
        let secondaryMem: String = {
          if memMB <= 0 { return "" }
          if memMB >= 1024 {
            let gb = memMB / 1024
            let gbText = gb < 10 ? String(format: "%.1f", gb) : String(format: "%.0f", gb)
            return " · \(gbText) GB"
          } else {
            return String(format: " · %.0f MB", memMB)
          }
        }()
        return "\(model.totalSize) · \(runningContext)\(secondaryMem)"
      }
      return model.totalSize
    }()

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
      // Second line: always show downloaded/total in GB with two decimals.
      // When the network hasn't reported a total yet (0), fall back to catalog size.
      let completedText = ByteFormatters.gbTwoDecimals(progress.completedUnitCount)
      let totalBytes: Int64 = {
        if progress.totalUnitCount > 0 {
          return progress.totalUnitCount
        } else {
          // fileSizeMB is our catalog estimate for the full model (all parts).
          return Int64(model.fileSizeMB) * 1_000_000
        }
      }()
      let totalText = ByteFormatters.gbTwoDecimals(totalBytes)
      bytesLabel.stringValue = "\(completedText) / \(totalText)"
      bytesLabel.isHidden = false
      // Removed indicator image in favor of simplified state display
      updateActionsVisibility(for: .downloading(progress), highlighted: isHoverHighlighted)
    case .downloaded:
      progressLabel.stringValue = ""
      bytesLabel.stringValue = defaultSecondary
      bytesLabel.isHidden = false
      // No play/stop affordance; active state is conveyed by circular icon.

      updateActionsVisibility(for: .downloaded, highlighted: isHoverHighlighted)
    case .available:
      progressLabel.stringValue = ""
      bytesLabel.stringValue = defaultSecondary
      bytesLabel.isHidden = false

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
    // Show a stop trailing visual instead of ellipsis when this model is running.
    let isActive = server.isActive(model: model)
    let isRunning = isActive && server.isRunning
    switch status {
    case .downloading:
      actionsExpanded = false
      setEllipsisVisible(false)
      stopButton.isHidden = true
      revealButton.isHidden = true
      deleteButton.isHidden = true
      maxContextButton.isHidden = true
    case .available:
      actionsExpanded = false
      setEllipsisVisible(false)
      stopButton.isHidden = true
      revealButton.isHidden = true
      deleteButton.isHidden = true
      maxContextButton.isHidden = true
    case .downloaded:
      if isRunning {
        // When running, no ellipsis; show stop glyph on hover and when not hovered too?
        // Requirement: when a model is running, it should not show an ellipsis button on hover.
        // We show a stop symbol as trailing visual. Keep it visible to indicate selectable stop.
        setEllipsisVisible(false)
        stopButton.isHidden = false
        revealButton.isHidden = true
        deleteButton.isHidden = true
        maxContextButton.isHidden = true
      } else if highlighted {
        stopButton.isHidden = true
        setEllipsisVisible(!actionsExpanded)
        revealButton.isHidden = !actionsExpanded
        deleteButton.isHidden = !actionsExpanded
        maxContextButton.isHidden = !actionsExpanded
      } else {
        stopButton.isHidden = true
        actionsExpanded = false
        setEllipsisVisible(false)
        revealButton.isHidden = true
        deleteButton.isHidden = true
        maxContextButton.isHidden = true
      }
    }
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

  // Neutral adaptive tint for action symbols; avoid strong destructive red by default.
  private func applyActionTints() {
    // Determine which action buttons are visible, then tint their image views
    let visibleImageViews: [NSImageView] = [
      // stopButton has its own inner image view; tint via its subviews
      !revealButton.isHidden ? revealImageView : nil,
      !deleteButton.isHidden ? deleteImageView : nil,
      !maxContextButton.isHidden ? maxContextImageView : nil,
    ].compactMap { $0 }
    guard !visibleImageViews.isEmpty else {
      // Still update ellipsis tint if it's visible
      if !ellipsisContainer.isHidden {
        ellipsisImageView.contentTintColor = isHoverHighlighted ? .labelColor : .secondaryLabelColor
      }
      // Also tint stopButton inner image if visible
      if !stopButton.isHidden, let iv = stopButton.subviews.compactMap({ $0 as? NSImageView }).first {
        iv.contentTintColor = isHoverHighlighted ? .systemRed : .systemRed
      }
      return
    }
    let tint = isHoverHighlighted ? NSColor.labelColor : NSColor.secondaryLabelColor
    visibleImageViews.forEach { $0.contentTintColor = tint }
    // Keep ellipsis same tinting rules as other action buttons
    if !ellipsisContainer.isHidden { ellipsisImageView.contentTintColor = tint }
    if !stopButton.isHidden, let iv = stopButton.subviews.compactMap({ $0 as? NSImageView }).first { iv.contentTintColor = .systemRed }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyActionTints()
    // Tints auto-update using dynamic NSColors
    if !ellipsisContainer.isHidden {
      ellipsisImageView.contentTintColor = isHoverHighlighted ? .labelColor : .secondaryLabelColor
    }
    if !stopButton.isHidden, let iv = stopButton.subviews.compactMap({ $0 as? NSImageView }).first {
      iv.contentTintColor = .systemRed
    }
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

  @objc private func handleStop() {
    let isActive = server.isActive(model: model)
    guard isActive else { return }
    server.stop()
    refresh()
  }

  @objc private func handleRevealInFinder() {
    let url = URL(fileURLWithPath: model.modelFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @objc private func handleRunAtMaxContext() {
    actionsExpanded = false
    server.start(model: model, contextLength: 0)
    refresh()
  }
}
