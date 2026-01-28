import AppKit
import Foundation

/// Interactive menu item representing a single model (installed, downloading, or available).
/// Visual states:
/// - Available: rounded square icon (inactive) + label
/// - Downloading: rounded square icon (inactive) + progress
/// - Installed: rounded square icon (inactive) + label
/// - Loading: rounded square icon (active)
/// - Running: rounded square icon (active)
final class ModelItemView: ItemView, NSGestureRecognizerDelegate {
  private let model: CatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let actionHandler: ModelActionHandler
  private let isInCatalog: Bool

  // Internal state for expansion
  private let isExpanded: Bool
  private let onExpand: (() -> Void)?

  // Labels
  private let titleLabel = Theme.primaryLabel()
  private let subtitleLabel: NSTextField = {
    let label = Theme.secondaryLabel()
    // Single line with ellipsis truncation when hover buttons overlap
    label.maximumNumberOfLines = 1
    label.lineBreakMode = .byTruncatingTail
    label.cell?.truncatesLastVisibleLine = true
    // Prevent letter spacing compression before truncation
    label.allowsDefaultTighteningForTruncation = false
    return label
  }()
  private let progressLabel: NSTextField = {
    let label = Theme.secondaryLabel()
    label.font = Theme.Fonts.primary
    label.alignment = .right
    return label
  }()

  // Icon and action buttons
  private let iconView = IconView()
  private let cancelImageView = NSImageView()
  private let unloadButton = NSButton()

  // Hover action buttons (shown on hover for installed models)
  private let copyIdButton = NSButton()
  private let deleteButton = NSButton()
  private let hoverButtonsStack = NSStackView()

  init(
    model: CatalogEntry, server: LlamaServer, modelManager: ModelManager,
    actionHandler: ModelActionHandler, isInCatalog: Bool = false,
    isExpanded: Bool = false, onExpand: (() -> Void)? = nil
  ) {
    self.model = model
    self.server = server
    self.modelManager = modelManager
    self.actionHandler = actionHandler
    self.isInCatalog = isInCatalog
    self.isExpanded = isExpanded
    self.onExpand = onExpand
    super.init(frame: .zero)

    iconView.imageView.image = NSImage(named: model.icon)

    // Configure action buttons
    Theme.configure(cancelImageView, symbol: "xmark", color: .systemRed)
    Theme.configure(unloadButton, symbol: "stop.circle", tooltip: "Unload model")

    unloadButton.target = self
    unloadButton.action = #selector(didClickUnload)

    // Configure hover action buttons
    Theme.configure(copyIdButton, symbol: "doc.on.doc", tooltip: "Copy model ID")
    Theme.configure(deleteButton, symbol: "trash", tooltip: "Delete model")

    copyIdButton.target = self
    copyIdButton.action = #selector(didClickCopyId)
    deleteButton.target = self
    deleteButton.action = #selector(didClickDelete)

    // Configure hover buttons stack
    hoverButtonsStack.orientation = .horizontal
    hoverButtonsStack.spacing = 4
    hoverButtonsStack.addArrangedSubview(copyIdButton)
    hoverButtonsStack.addArrangedSubview(deleteButton)

    // Start hidden
    cancelImageView.isHidden = true
    unloadButton.isHidden = true
    progressLabel.isHidden = true
    hoverButtonsStack.isHidden = true

    setupLayout()
    setupGestures()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 40) }

  private func setupLayout() {
    // Text column
    let textColumn = NSStackView(views: [titleLabel, subtitleLabel])
    textColumn.orientation = .vertical
    textColumn.alignment = .leading
    textColumn.spacing = Layout.textLineSpacing

    // Leading: Icon + Text
    let leading = NSStackView(views: [iconView, textColumn])
    leading.orientation = .horizontal
    leading.alignment = .centerY
    leading.spacing = 6

    // Spacer
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Accessory stack
    let accessoryStack = NSStackView(views: [
      progressLabel, cancelImageView, hoverButtonsStack, unloadButton,
    ])
    accessoryStack.orientation = .horizontal
    accessoryStack.alignment = .centerY
    accessoryStack.spacing = 6

    // Root stack
    let rootStack = NSStackView(views: [leading, spacer, accessoryStack])
    rootStack.orientation = .horizontal
    rootStack.alignment = .centerY
    rootStack.spacing = 6

    contentView.addSubview(rootStack)
    rootStack.pinToSuperview()

    // Constraints
    Layout.constrainToIconSize(cancelImageView)
    Layout.constrainToIconSize(unloadButton)
    Layout.constrainToIconSize(copyIdButton)
    Layout.constrainToIconSize(deleteButton)
    progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.progressWidth).isActive =
      true

    titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    // Allow subtitle to compress and truncate when hover buttons appear
    subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    progressLabel.setContentHuggingPriority(.required, for: .horizontal)
    progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    cancelImageView.setContentHuggingPriority(.required, for: .horizontal)
    cancelImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
  }

  private func setupGestures() {
    let rowClickRecognizer = addGesture(action: #selector(didClickRow))
    rowClickRecognizer.delegate = self
  }

  @objc private func didClickRow() {
    if !model.isCompatible() && !modelManager.isInstalled(model) {
      NSSound.beep()
      return
    }

    if modelManager.isInstalled(model) {
      onExpand?()
    } else {
      actionHandler.performPrimaryAction(for: model)
      refresh()
    }
  }

  @objc private func didClickUnload() {
    actionHandler.performPrimaryAction(for: model)
  }

  @objc private func didClickCopyId() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(model.id, forType: .string)

    // Show checkmark feedback
    copyIdButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")

    // Restore copy icon after delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.copyIdButton.image = NSImage(
        systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy model ID")
    }
  }

  @objc private func didClickDelete() {
    actionHandler.delete(model: model)
  }

  // Prevent row toggle when clicking action buttons
  func gestureRecognizer(
    _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
  ) -> Bool {
    let loc = event.locationInWindow
    let actionButtons = [unloadButton, copyIdButton, deleteButton]
    return !actionButtons.contains { view in
      !view.isHidden && view.bounds.contains(view.convert(loc, from: nil))
    }
  }

  func refresh() {
    let isActive = server.isActive(model: model)
    let isLoading = server.isLoading(model: model)
    let progress = modelManager.downloadProgress(for: model)
    let isDownloading = progress != nil
    let isInstalled = modelManager.isInstalled(model)

    // If the item was downloading and is now available (cancelled), it will be removed from the list.
    // We preserve the "downloading" styling to avoid a flicker of the "available" styling (primary color)
    // before the item disappears.
    let wasDownloading = !cancelImageView.isHidden
    let isCancelled = wasDownloading && !isDownloading && !isInstalled

    // If the item is in the catalog section, we don't want to show it as downloading yet.
    // It will be moved to the installed section in the next frame.
    let showAsDownloading = !isInCatalog && (isDownloading || isCancelled)

    let baseTextColor = showAsDownloading ? Theme.Colors.textSecondary : Theme.Colors.textPrimary
    let isCompatible = model.isCompatible()
    let textColor = isCompatible ? baseTextColor : Theme.Colors.textSecondary

    titleLabel.attributedStringValue = Format.modelName(
      family: model.family,
      size: model.sizeLabel,
      familyColor: textColor,
      sizeColor: textColor,
      hasVision: model.hasVisionSupport,
      quantization: model.quantizationLabel
    )

    // Determine if this model is currently running
    let isRunning = server.isActive(model: model)

    let incompatibility = !isCompatible ? model.incompatibilitySummary() : nil
    subtitleLabel.attributedStringValue = Format.modelMetadata(
      for: model,
      color: textColor,
      incompatibility: incompatibility,
      isRunning: isRunning
    )

    if let progress {
      progressLabel.stringValue = Format.progressText(progress)
    }
    progressLabel.isHidden = !showAsDownloading
    cancelImageView.isHidden = !showAsDownloading
    unloadButton.isHidden = !isActive

    iconView.inactiveTintColor =
      isCompatible ? Theme.Colors.modelIconTint : Theme.Colors.textSecondary

    // Update icon state
    iconView.setLoading(isLoading)
    iconView.isActive = isActive

    needsDisplay = true
  }

  override var highlightEnabled: Bool {
    // Disable highlight for incompatible models that are not installed
    if !model.isCompatible() && !modelManager.isInstalled(model) {
      return false
    }
    return true
  }

  override func highlightDidChange(_ highlighted: Bool) {
    // Show hover buttons only for installed models that aren't active/downloading
    let isInstalled = modelManager.isInstalled(model)
    let isActive = server.isActive(model: model)
    let isDownloading = modelManager.isDownloading(model)
    let showHoverButtons = highlighted && isInstalled && !isActive && !isDownloading
    hoverButtonsStack.isHidden = !showHoverButtons
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .systemRed
    unloadButton.contentTintColor = .tertiaryLabelColor
    copyIdButton.contentTintColor = .tertiaryLabelColor
    deleteButton.contentTintColor = .tertiaryLabelColor
  }
}
