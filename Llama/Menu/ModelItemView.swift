import AppKit
import Foundation

/// Interactive menu item representing a single installed/downloading model.
/// Visual states:
/// - Downloading: rounded square icon (inactive) + progress
/// - Installed: rounded square icon (inactive) + label
/// - Loading: rounded square icon (active)
/// - Running: rounded square icon (active)
final class ModelItemView: ItemView, NSGestureRecognizerDelegate {
  private let model: Model
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let actionHandler: ModelActionHandler

  // Internal state for expansion
  private let isExpanded: Bool
  private let onExpand: (() -> Void)?

  // Labels
  private let titleLabel: NSTextField = {
    let label = Theme.primaryLabel()
    // Single line with ellipsis truncation when title is too long to fit
    label.maximumNumberOfLines = 1
    label.lineBreakMode = .byTruncatingTail
    label.cell?.truncatesLastVisibleLine = true
    // Prevent letter spacing compression before truncation
    label.allowsDefaultTighteningForTruncation = false
    return label
  }()
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

  // Icon and action buttons
  private let iconView = IconView()
  private let cancelImageView = NSImageView()
  /// Combined pause/play affordance: `pause.circle` while a download is in flight,
  /// `play.circle` when the row is paused (partials on disk, no transfer). Always
  /// visible on downloading rows, anchored at the trailing edge so it doesn't shift
  /// when the hover-only cancel X appears beside it. Clicking it toggles, same as a
  /// row-body click.
  private let pausePlayImageView = NSImageView()
  /// Slim progress bar shown while a download is in flight, on the right of the
  /// row. Replaces the old inline "42%" text so the size-on-disk readout can stay
  /// fixed on the left instead of shifting to make room for a percentage.
  private let progressBar = ProgressBarView()
  private let unloadButton = NSButton()

  // Hover action buttons (shown on hover for installed models)
  private let copyIdButton = NSButton()
  private let deleteButton = NSButton()
  private let hoverButtonsStack = NSStackView()

  /// Whether the row is currently styled as downloading (in flight, paused, or in the
  /// brief post-cancel window). Set by `refresh()`; read back both to detect the
  /// cancelled transition and to gate the hover-only cancel X in `highlightDidChange`.
  private var showAsDownloading = false

  init(
    model: Model, server: LlamaServer, modelManager: ModelManager,
    actionHandler: ModelActionHandler,
    isExpanded: Bool = false, onExpand: (() -> Void)? = nil
  ) {
    self.model = model
    self.server = server
    self.modelManager = modelManager
    self.actionHandler = actionHandler
    self.isExpanded = isExpanded
    self.onExpand = onExpand
    super.init(frame: .zero)

    iconView.imageView.image =
      model.brandLogoAsset.flatMap { NSImage(named: $0) }
      ?? NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "Model")

    // Configure action buttons
    Theme.configure(
      cancelImageView, symbol: "xmark.circle.fill", tooltip: "Cancel download",
      color: .tertiaryLabelColor)
    // Pause/play icon: actual symbol and tooltip are set in `refresh()` based on status.
    Theme.configure(pausePlayImageView, symbol: "pause.circle", color: .tertiaryLabelColor)
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
    pausePlayImageView.isHidden = true
    progressBar.isHidden = true
    unloadButton.isHidden = true
    hoverButtonsStack.isHidden = true

    setupLayout()
    setupGestures()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setupLayout() {
    // Subtitle line: the metadata/size label with the download progress bar
    // trailing it. The bar sits right next to the size-on-disk readout (line two)
    // rather than off on the row's right edge, and is hidden when not downloading.
    let subtitleRow = NSStackView(views: [progressBar, subtitleLabel])
    subtitleRow.orientation = .horizontal
    subtitleRow.alignment = .centerY
    subtitleRow.spacing = 6
    // Hidden views collapse in the stack, so on installed rows (bar hidden) the
    // subtitle sits flush at the leading edge as before.

    // Text column
    let textColumn = NSStackView(views: [titleLabel, subtitleRow])
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

    // Accessory stack — the hover-only cancel X (see `highlightDidChange`) precedes
    // the always-on pause/play toggle, so the toggle stays anchored at the trailing
    // edge and doesn't shift when the X appears. The progress bar lives on the
    // subtitle line (see `subtitleRow`), next to the size-on-disk readout.
    let accessoryStack = NSStackView(views: [
      cancelImageView, pausePlayImageView, hoverButtonsStack, unloadButton,
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

    // Pin to a fixed row size. The width clamp prevents a long title from
    // widening the menu; the height clamp gives every row a consistent 40pt rhythm.
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Layout.menuWidth),
      heightAnchor.constraint(equalToConstant: 40),
    ])

    // Constraints
    Layout.constrainToIconSize(cancelImageView)
    Layout.constrainToIconSize(pausePlayImageView)
    Layout.constrainToIconSize(unloadButton)
    Layout.constrainToIconSize(copyIdButton)
    Layout.constrainToIconSize(deleteButton)

    titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    // Allow subtitle to compress and truncate when hover buttons appear
    subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    cancelImageView.setContentHuggingPriority(.required, for: .horizontal)
    cancelImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
    pausePlayImageView.setContentHuggingPriority(.required, for: .horizontal)
    pausePlayImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
  }

  private func setupGestures() {
    let rowClickRecognizer = addGesture(action: #selector(didClickRow))
    rowClickRecognizer.delegate = self

    // Dedicated click target on the cancel X so paused rows can be cancelled explicitly
    // (the row body itself resumes a paused download — opposite action, same row).
    let cancelClick = NSClickGestureRecognizer(target: self, action: #selector(didClickCancel))
    cancelImageView.addGestureRecognizer(cancelClick)

    // Pause/play button. Same action as clicking the row body; the button just makes
    // the affordance discoverable without requiring the user to guess that "click
    // the row" pauses/resumes.
    let pausePlayClick = NSClickGestureRecognizer(
      target: self, action: #selector(didClickPausePlay))
    pausePlayImageView.addGestureRecognizer(pausePlayClick)
  }

  @objc private func didClickRow() {
    let isInstalled = modelManager.isInstalled(model)

    if !model.isCompatible() && !isInstalled {
      NSSound.beep()
      return
    }

    if isInstalled {
      onExpand?()
    } else {
      actionHandler.performPrimaryAction(for: model)
      refresh()
    }
  }

  @objc private func didClickCancel() {
    // Explicit discard — works for both active downloads and paused (interrupted) ones.
    // In both cases we want the `.partial` staging dir gone and the row removed.
    actionHandler.cancelDownload(for: model)
  }

  @objc private func didClickPausePlay() {
    // Same toggle as row-body click — performPrimaryAction already dispatches to
    // pause (when downloading) or resume (when paused). The button just makes the
    // affordance discoverable; it's not a separate code path.
    actionHandler.performPrimaryAction(for: model)
    refresh()
  }

  @objc private func didClickUnload() {
    actionHandler.performPrimaryAction(for: model)
  }

  @objc private func didClickCopyId() {
    Clipboard.copy(model.id)
    Theme.updateCopyIcon(copyIdButton, showingConfirmation: true)

    // Restore copy icon after delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self else { return }
      Theme.updateCopyIcon(self.copyIdButton, showingConfirmation: false)
    }
  }

  @objc private func didClickDelete() {
    actionHandler.delete(model: model)
  }

  // Prevent row toggle when clicking action buttons. Each listed view owns its own
  // click gesture — excluding it here stops the row-body gesture from also firing.
  func gestureRecognizer(
    _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
  ) -> Bool {
    let loc = event.locationInWindow
    let actionTargets: [NSView] = [
      unloadButton, copyIdButton, deleteButton, cancelImageView, pausePlayImageView,
    ]
    return !actionTargets.contains { view in
      !view.isHidden && view.bounds.contains(view.convert(loc, from: nil))
    }
  }

  func refresh() {
    let isActive = server.isActive(model: model)
    let isLoading = server.isLoading(model: model)
    let status = modelManager.status(for: model)

    // Derive row state from a single status switch. `fraction` drives the progress
    // bar fill; nil means "unknown" (downloading before first response, or paused
    // with a zero total) and reads as the minimum dot. `downloadedBytes` feeds the
    // "N of total" subtitle. Paused and downloading share the same in-flight
    // styling; only the label text and the pause/play icon differ.
    var isDownloading = false
    var isPaused = false
    var isInstalled = false
    var fraction: Double?
    var downloadedBytes: Int64 = 0
    switch status {
    case .available:
      break
    case .downloading(let progress):
      isDownloading = true
      downloadedBytes = progress.completedUnitCount
      if progress.totalUnitCount > 0 {
        fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
      }
    case .paused(let bytes, let total):
      isPaused = true
      downloadedBytes = bytes
      if total > 0 { fraction = Double(bytes) / Double(total) }
    case .installed:
      isInstalled = true
    }

    // If the item was downloading and is now available (cancelled), it will be removed from the list.
    // We preserve the "downloading" styling to avoid a flicker of the "available" styling (primary color)
    // before the item disappears.
    let wasDownloading = showAsDownloading
    let isCancelled = wasDownloading && !isDownloading && !isPaused && !isInstalled

    showAsDownloading = isDownloading || isPaused || isCancelled

    let baseTextColor = showAsDownloading ? Theme.Colors.textSecondary : Theme.Colors.textPrimary
    let isCompatible = model.isCompatible()
    let textColor = isCompatible ? baseTextColor : Theme.Colors.textSecondary

    // Quant renders as a dimmed suffix (the id's post-colon part), but only
    // when it carries information — full-precision builds have nothing to say.
    titleLabel.attributedStringValue = Format.modelName(
      idBase: model.idBase,
      color: textColor,
      quant: model.quantization.isEmpty ? nil : model.quantization,
      hasVision: model.hasVisionSupport
    )

    let incompatibility = !isCompatible ? model.incompatibilitySummary() : nil
    // Subtitle swaps between size+ctx (for installed/available rows) and a
    // transfer readout while a download is in flight: "1.2 GB of 3.1 GB", or
    // "Paused" when interrupted. The progress bar leads it (see `subtitleRow`).
    // Ctx tier is only meaningful once fully downloaded, so it's omitted here.
    if showAsDownloading {
      subtitleLabel.attributedStringValue = Format.downloadSubtitle(
        downloadedBytes: downloadedBytes,
        totalBytes: model.fileSize,
        paused: isPaused,
        color: textColor
      )
    } else {
      subtitleLabel.attributedStringValue = Format.modelMetadata(
        for: model,
        incompatibility: incompatibility
      )
    }

    // Cancel X is hover-only, matching the copy/delete hover buttons on installed rows.
    cancelImageView.isHidden = !(showAsDownloading && isHighlighted)

    // Progress bar shows whenever the row is styled as downloading. A nil fraction
    // (download not yet reporting, or a paused zero-total) reads as empty.
    progressBar.isHidden = !showAsDownloading
    if showAsDownloading {
      progressBar.fraction = fraction ?? 0
    }

    // Pause/play icon swaps based on live vs. paused state. Hidden during the post-cancel
    // flicker window (isCancelled) so the about-to-disappear row doesn't show a resume arrow.
    let showPausePlay = isDownloading || isPaused
    pausePlayImageView.isHidden = !showPausePlay
    if showPausePlay {
      let symbol = isDownloading ? "pause.circle" : "play.circle"
      let tooltip = isDownloading ? "Pause download" : "Resume download"
      pausePlayImageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      pausePlayImageView.toolTip = tooltip
    }

    unloadButton.isHidden = !isActive

    iconView.inactiveTintColor =
      isCompatible ? Theme.Colors.modelIconTint : Theme.Colors.textSecondary

    // Update icon state
    iconView.setLoading(isLoading)
    iconView.isActive = isActive

    needsDisplay = true
  }

  override var highlightEnabled: Bool {
    // Incompatible, not-installed rows can't be acted on -- no highlight.
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

    // Cancel X is the downloading-row hover affordance (see `refresh()` for the
    // same gate on state changes while hovered).
    cancelImageView.isHidden = !(highlighted && showAsDownloading)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .tertiaryLabelColor
    unloadButton.contentTintColor = .tertiaryLabelColor
    copyIdButton.contentTintColor = .tertiaryLabelColor
    deleteButton.contentTintColor = .tertiaryLabelColor
  }
}
