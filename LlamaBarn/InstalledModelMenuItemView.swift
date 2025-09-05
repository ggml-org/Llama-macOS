import AppKit
import Foundation

/// Menu row representing a single installed model.
/// Visual states:
/// - Idle: icon + label + play symbol
/// - Loading: icon + label + spinner + stop symbol
/// - Running: icon + label + green circle + stop symbol
final class InstalledModelMenuItemView: NSView {
  // Shared font metrics
  private enum Font {
    static let primary = NSFont.systemFont(ofSize: 13)
    static let secondary = NSFont.systemFont(ofSize: 10, weight: .medium)
  }
  private let model: ModelCatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  // Subviews
  private let backgroundView = NSView()
  private let iconView = NSImageView()
  private let labelField = NSTextField(labelWithString: "")
  private let stateContainer = NSView()
  private let spinner = NSProgressIndicator()
  private let greenDot = NSView()
  private let indicatorImageView = NSImageView()
  private let progressLabel = NSTextField(labelWithString: "")
  // Second-line label: used for progress during downloads and for
  // consistent two-line layout (size/badges) when idle/running.
  private let bytesLabel = NSTextField(labelWithString: "")
  // Replaces prior NSButton (which rendered black in dark mode inside menu views) with template image view.
  private let deleteImageView = NSImageView()

  private var trackingArea: NSTrackingArea?
  private var isHighlighted: Bool = false { didSet { updateHighlight() } }

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
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.wantsLayer = true
    iconView.image = NSImage(named: model.icon)
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    iconView.imageScaling = .scaleProportionallyDown
    // Normalize logo contrast by forcing template rendering so we can tint.
    if let img = iconView.image { img.isTemplate = true }
    iconView.contentTintColor = .secondaryLabelColor

    labelField.stringValue = model.displayName
    labelField.font = Font.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.isDisplayedWhenStopped = false

    greenDot.wantsLayer = true
    greenDot.translatesAutoresizingMaskIntoConstraints = false
    greenDot.layer?.cornerRadius = 4
    greenDot.layer?.backgroundColor = NSColor.llamaGreen.cgColor

    indicatorImageView.translatesAutoresizingMaskIntoConstraints = false
    indicatorImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    indicatorImageView.contentTintColor = .controlAccentColor

    progressLabel.font = Font.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    bytesLabel.font = Font.secondary
    bytesLabel.textColor = .secondaryLabelColor
    bytesLabel.alignment = .left
    bytesLabel.translatesAutoresizingMaskIntoConstraints = false
    bytesLabel.isHidden = false

    deleteImageView.image = NSImage(
      systemSymbolName: "trash", accessibilityDescription: "Delete model")
    deleteImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    if let img = deleteImageView.image { img.isTemplate = true }
    deleteImageView.translatesAutoresizingMaskIntoConstraints = false
    // Start with a low-emphasis tertiary tint; hover/highlight will elevate contrast slightly.
    deleteImageView.contentTintColor = .tertiaryLabelColor
    deleteImageView.toolTip = "Delete model"
    deleteImageView.isHidden = true

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

    let leading = NSStackView(views: [iconView, nameStack])
    leading.translatesAutoresizingMaskIntoConstraints = false
    leading.orientation = .horizontal
    leading.alignment = .top
    leading.spacing = 6

    // Right: status/progress/delete/action in a row
    let rightStack = NSStackView(views: [stateContainer, progressLabel, deleteImageView, indicatorImageView])
    rightStack.translatesAutoresizingMaskIntoConstraints = false
    rightStack.orientation = .horizontal
    rightStack.spacing = 6
    rightStack.alignment = .centerY

    let rootStack = NSStackView(views: [leading, spacer, rightStack])
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    rootStack.orientation = .horizontal
    rootStack.spacing = 6
    rootStack.alignment = .centerY
    addSubview(backgroundView)
    backgroundView.addSubview(rootStack)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
      // Reduced from 18 -> 16 to make logos a bit smaller and align visually with 16x16 action icons
      iconView.widthAnchor.constraint(equalToConstant: 16),
      iconView.heightAnchor.constraint(equalToConstant: 16),
      stateContainer.widthAnchor.constraint(equalToConstant: 16),
      stateContainer.heightAnchor.constraint(equalToConstant: 16),
      indicatorImageView.widthAnchor.constraint(equalToConstant: 16),
      indicatorImageView.heightAnchor.constraint(equalToConstant: 16),
      deleteImageView.widthAnchor.constraint(equalToConstant: 16),
      deleteImageView.heightAnchor.constraint(equalToConstant: 16),
      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 48),
      rootStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
      rootStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),
      rootStack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 4),
      rootStack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -4),
    ])
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
    let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
    addTrackingArea(trackingArea!)
  }

  override func mouseEntered(with event: NSEvent) { isHighlighted = true }
  override func mouseExited(with event: NSEvent) { isHighlighted = false }

  // Custom hit test so clicking the trash icon deletes instead of toggling run state.
  override func mouseDown(with event: NSEvent) {
    let loc = convert(event.locationInWindow, from: nil)
    if !deleteImageView.isHidden && deleteImageView.frame.contains(loc) {
      handleDelete()
      return
    }
    toggle()
  }

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

  private func updateHighlight() {
    // Use a neutral adaptive highlight instead of accent color blue. We derive from labelColor so it
    // inverts appropriately in light/dark without introducing a semantic (accent/destructive) hue.
    if isHighlighted {
      backgroundView.layer?.backgroundColor = NSColor.cgColor(.lbHoverBackground, in: backgroundView)
    } else {
      backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
    }
    backgroundView.layer?.cornerRadius = 6
    // Show delete only when hovered & model is downloaded
    let status = modelManager.getModelStatus(model)
    if case .downloaded = status {
      deleteImageView.isHidden = !isHighlighted
    } else {
      deleteImageView.isHidden = true
    }
    // Update icon tint when highlight changes.
    applyIconTint()
    applyDeleteTint()
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
    } else if isRunning {
      stateContainer.addSubview(greenDot)
      NSLayoutConstraint.activate([
        greenDot.widthAnchor.constraint(equalToConstant: 8),
        greenDot.heightAnchor.constraint(equalToConstant: 8),
        greenDot.centerXAnchor.constraint(equalTo: stateContainer.centerXAnchor),
        greenDot.centerYAnchor.constraint(equalTo: stateContainer.centerYAnchor),
      ])
    }
    // Compose a default secondary line (size + capability badges) used when not downloading
    let defaultSecondary: String = {
      var secondary = "\(model.totalSize)"
      if model.supportsVision { secondary += " · 👓" }
      if model.supportsAudio { secondary += " · 🔊" }
      return secondary
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
      // Second line: show downloaded/total bytes
      let formatter = ByteCountFormatter()
      formatter.allowedUnits = [.useMB, .useGB]
      formatter.countStyle = .decimal
      let completedText = formatter.string(fromByteCount: progress.completedUnitCount)
      if progress.totalUnitCount > 0 {
        let totalText = formatter.string(fromByteCount: progress.totalUnitCount)
        bytesLabel.stringValue = "\(completedText) / \(totalText)"
      } else {
        bytesLabel.stringValue = completedText
      }
      bytesLabel.isHidden = false
      indicatorImageView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
      indicatorImageView.contentTintColor = .systemRed
      deleteImageView.isHidden = true
    case .downloaded:
      // If this model is currently running, show live RAM usage on the right.
      if isRunning && server.memoryUsageMB > 0 {
        let memMB = server.memoryUsageMB
        let (value, unit): (Double, String) = memMB >= 1024 ? (memMB / 1024, "GB") : (memMB, "MB")
        let valueStr: String = {
          if unit == "GB" && value < 10 { return String(format: "%.1f", value) }
          return String(format: "%.0f", value)
        }()
        progressLabel.stringValue = "\(valueStr) \(unit)"
      } else {
        progressLabel.stringValue = ""
      }
      bytesLabel.stringValue = defaultSecondary
      bytesLabel.isHidden = false
      let symbolName = (isLoadingServer || isRunning) ? "stop" : "play"
      indicatorImageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
      indicatorImageView.contentTintColor =
        (isLoadingServer || isRunning) ? .systemRed : .controlAccentColor
      // Only show on hover via updateHighlight
      if isHighlighted { deleteImageView.isHidden = false }
    case .available:
      progressLabel.stringValue = ""
      bytesLabel.stringValue = defaultSecondary
      bytesLabel.isHidden = false
      indicatorImageView.image = nil
      deleteImageView.isHidden = true
    }
    applyIconTint(isActive: isLoadingServer || isRunning)
    needsDisplay = true
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
      statusIsActive = isActiveModel && (server.isLoading || server.isRunning)
    }
    if statusIsActive || isHighlighted {
      iconView.contentTintColor = .labelColor
    } else {
      iconView.contentTintColor = .secondaryLabelColor
    }
  }

  // Neutral adaptive tint for the delete (trash) symbol; avoid semantic "destructive" red to reduce visual noise.
  private func applyDeleteTint() {
    guard !deleteImageView.isHidden else { return }
    let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    if isHighlighted {
      deleteImageView.contentTintColor = increaseContrast ? .labelColor : .secondaryLabelColor
    } else {
      deleteImageView.contentTintColor =
        increaseContrast ? .secondaryLabelColor : .tertiaryLabelColor
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyDeleteTint()
  }

  @objc private func handleDelete() {
    let status = modelManager.getModelStatus(model)
    guard case .downloaded = status else { return }
    modelManager.deleteDownloadedModel(model)
    membershipChanged()
  }
}
