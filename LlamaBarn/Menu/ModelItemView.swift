import AppKit
import Foundation

/// Interactive menu item representing a single model (installed, downloading, or available).
/// Visual states:
/// - Available: rounded square icon (inactive) + label
/// - Downloading: rounded square icon (inactive) + progress
/// - Installed: rounded square icon (inactive) + label
/// - Loading: rounded square icon (active)
/// - Running: rounded square icon (active)
final class ModelItemView: StandardItemView, NSGestureRecognizerDelegate {
  private let model: CatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let actionHandler: ModelActionHandler
  private let isInCatalog: Bool

  // Subviews
  private let progressLabel: NSTextField = {
    let label = Theme.secondaryLabel()
    label.font = Theme.Fonts.primary
    return label
  }()
  private let cancelImageView = NSImageView()
  private let finderImageView = NSImageView()
  private let deleteImageView = NSImageView()

  // Hover handling is provided by MenuItemView
  private var showingDeleteButton = false

  init(
    model: CatalogEntry, server: LlamaServer, modelManager: ModelManager,
    actionHandler: ModelActionHandler, isInCatalog: Bool = false
  ) {
    self.model = model
    self.server = server
    self.modelManager = modelManager
    self.actionHandler = actionHandler
    self.isInCatalog = isInCatalog
    super.init(frame: .zero)

    iconView.imageView.image = NSImage(named: model.icon)
    progressLabel.alignment = .right

    Theme.configure(cancelImageView, symbol: "xmark", color: .systemRed)
    Theme.configure(finderImageView, symbol: "folder", tooltip: "Show in Finder")
    Theme.configure(deleteImageView, symbol: "trash", tooltip: "Delete model")

    // Start hidden
    cancelImageView.isHidden = true
    finderImageView.isHidden = true
    deleteImageView.isHidden = true
    progressLabel.isHidden = true

    accessoryStack.addArrangedSubview(progressLabel)
    accessoryStack.addArrangedSubview(cancelImageView)
    accessoryStack.addArrangedSubview(finderImageView)
    accessoryStack.addArrangedSubview(deleteImageView)

    NSLayoutConstraint.activate([
      cancelImageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
      cancelImageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),

      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.progressWidth),

      finderImageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
      finderImageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),

      deleteImageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
      deleteImageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
    ])

    titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    progressLabel.setContentHuggingPriority(.required, for: .horizontal)
    progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    cancelImageView.setContentHuggingPriority(.required, for: .horizontal)
    cancelImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
    finderImageView.setContentHuggingPriority(.required, for: .horizontal)
    finderImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

    setupGestures()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 40) }

  private func setupGestures() {
    let rowClickRecognizer = addGesture(action: #selector(didClickRow))
    rowClickRecognizer.delegate = self

    addGesture(to: deleteImageView, action: #selector(didClickDelete))
    addGesture(to: finderImageView, action: #selector(didClickFinder))
    addGesture(action: #selector(didRightClick), buttonMask: 0x2)
  }

  @objc private func didClickRow() {
    if !model.isCompatible() && !modelManager.isInstalled(model) {
      NSSound.beep()
      return
    }
    actionHandler.performPrimaryAction(for: model)
    refresh()
  }

  @objc private func didClickDelete() {
    showingDeleteButton = false
    actionHandler.delete(model: model)
  }

  @objc private func didClickFinder() {
    actionHandler.showInFinder(model: model)
  }

  @objc private func didRightClick() {
    // Only toggle delete button for installed models
    guard modelManager.isInstalled(model) else { return }
    showingDeleteButton.toggle()
    refresh()
  }

  // Prevent row toggle when clicking the delete or finder buttons.
  func gestureRecognizer(
    _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
  ) -> Bool {
    let loc = event.locationInWindow

    let deletePoint = deleteImageView.convert(loc, from: nil)
    if deleteImageView.bounds.contains(deletePoint) && !deleteImageView.isHidden {
      return false
    }

    let finderPoint = finderImageView.convert(loc, from: nil)
    if finderImageView.bounds.contains(finderPoint) && !finderImageView.isHidden {
      return false
    }

    return true
  }

  func refresh() {
    let isActive = server.isActive(model: model)
    let isLoading = isActive && server.isLoading
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

    let incompatibility = !isCompatible ? model.incompatibilitySummary() : nil
    subtitleLabel.attributedStringValue = Format.modelMetadata(
      for: model,
      color: textColor,
      incompatibility: incompatibility
    )

    if let progress {
      progressLabel.stringValue = Format.progressText(progress)
    }
    progressLabel.isHidden = !showAsDownloading
    cancelImageView.isHidden = !showAsDownloading

    iconView.inactiveTintColor =
      isCompatible ? Theme.Colors.modelIconTint : Theme.Colors.textSecondary

    // Delete and finder buttons only for installed models on right-click
    // Reset showingDeleteButton if model is no longer installed
    if !isInstalled {
      showingDeleteButton = false
    }
    deleteImageView.isHidden = !showingDeleteButton
    finderImageView.isHidden = !showingDeleteButton

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
    // Reset delete button when mouse exits
    if !highlighted && showingDeleteButton {
      showingDeleteButton = false
      refresh()
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .systemRed
    finderImageView.contentTintColor = .tertiaryLabelColor
    deleteImageView.contentTintColor = .tertiaryLabelColor
  }
}
