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
  private let membershipChanged: (CatalogEntry) -> Void

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
  private var rowClickRecognizer: NSClickGestureRecognizer?
  private var deleteClickRecognizer: NSClickGestureRecognizer?
  private var finderClickRecognizer: NSClickGestureRecognizer?
  private var rightClickRecognizer: NSClickGestureRecognizer?
  private var showingDeleteButton = false

  init(
    model: CatalogEntry, server: LlamaServer, modelManager: ModelManager,
    membershipChanged: @escaping (CatalogEntry) -> Void
  ) {
    self.model = model
    self.server = server
    self.modelManager = modelManager
    self.membershipChanged = membershipChanged
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

    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 40) }

  // Row click recognizer to toggle, letting the delete button handle its own action.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if rowClickRecognizer == nil {
      rowClickRecognizer = addGesture(action: #selector(didClickRow))
      rowClickRecognizer?.delegate = self
    }
    if deleteClickRecognizer == nil {
      deleteClickRecognizer = addGesture(to: deleteImageView, action: #selector(didClickDelete))
    }
    if finderClickRecognizer == nil {
      finderClickRecognizer = addGesture(to: finderImageView, action: #selector(didClickFinder))
    }
    if rightClickRecognizer == nil {
      rightClickRecognizer = addGesture(action: #selector(didRightClick), buttonMask: 0x2)
    }
  }

  @objc private func didClickRow() { toggle() }

  @objc private func didClickDelete() { performDelete() }

  @objc private func didClickFinder() { performShowInFinder() }

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
    } else {
      // Available -> Download
      do {
        try modelManager.downloadModel(model)
        membershipChanged(model)
      } catch {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = error.localizedDescription
        if let error = error as? LocalizedError, let recoverySuggestion = error.recoverySuggestion {
          alert.informativeText = recoverySuggestion
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    }
    refresh()
  }

  func refresh() {
    let isActive = server.isActive(model: model)
    let isLoading = isActive && server.isLoading
    let isDownloading = modelManager.downloadProgress(for: model) != nil
    let textColor = isDownloading ? Theme.Colors.textSecondary : Theme.Colors.textPrimary

    titleLabel.attributedStringValue = Format.modelName(
      family: model.family,
      size: model.sizeLabel,
      familyColor: textColor,
      sizeColor: textColor,
      hasVision: model.hasVisionSupport,
      quantization: model.quantizationLabel
    )

    let metadata = NSMutableAttributedString(
      attributedString: Format.modelMetadata(for: model, color: textColor))

    subtitleLabel.attributedStringValue = metadata

    if let progress = modelManager.downloadProgress(for: model) {
      progressLabel.stringValue = Format.progressText(progress)
      progressLabel.isHidden = false
      cancelImageView.isHidden = false
    } else {
      progressLabel.stringValue = ""
      progressLabel.isHidden = true
      cancelImageView.isHidden = true
    }
    iconView.inactiveTintColor = Theme.Colors.modelIconTint

    // Delete and finder buttons only for installed models on right-click
    // Reset showingDeleteButton if model is no longer installed
    if !modelManager.isInstalled(model) {
      showingDeleteButton = false
    }
    deleteImageView.isHidden = !showingDeleteButton
    finderImageView.isHidden = !showingDeleteButton

    // Update icon state
    iconView.setLoading(isLoading)
    iconView.isActive = isActive

    needsDisplay = true
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

  @objc private func performDelete() {
    guard modelManager.isInstalled(model) else { return }
    showingDeleteButton = false
    modelManager.deleteDownloadedModel(model)
    membershipChanged(model)
  }

  @objc private func performShowInFinder() {
    guard modelManager.isInstalled(model) else { return }
    let url = URL(fileURLWithPath: model.modelFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
