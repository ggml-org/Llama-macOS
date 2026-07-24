import AppKit
import Foundation

/// Interactive menu item representing a single installed/downloading model.
/// Visual states:
/// - Downloading: progress ring with a pause/play glyph in place of the icon
/// - Installed: circular icon (inactive) + label
/// - Loading: circular icon (active, spinner)
/// - Running: circular icon (active)
///
/// Installed rows are pure navigation -- clicking opens the model's page, which
/// owns all actions (Chat, Copy ID, Unload, Delete). A persistent dimmed chevron
/// signals that the row leads to that page. The only in-row control is the
/// hover-only cancel X on downloading rows, since a download in flight has no
/// page to host it. Chevron and cancel are mutually exclusive -- a row is either
/// installed or downloading, never both.
final class ModelItemView: ItemView, NSGestureRecognizerDelegate {
  private let model: Model
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let actionHandler: ModelActionHandler

  private let onOpen: (() -> Void)?

  /// Whether the title shows the id's leftover tags ("it", "qat", ...).
  /// Set by the menu builder only when another installed row would otherwise
  /// render an identical title — see `Format.modelName`.
  private let showTags: Bool

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
    // Single line with ellipsis truncation when the title column is too narrow
    label.maximumNumberOfLines = 1
    label.lineBreakMode = .byTruncatingTail
    label.cell?.truncatesLastVisibleLine = true
    // Prevent letter spacing compression before truncation
    label.allowsDefaultTighteningForTruncation = false
    return label
  }()

  // Icon and the trailing accessories: a persistent chevron on installed rows
  // signalling the row opens the model's page, and the hover-only cancel X on
  // downloading rows. They're mutually exclusive -- a row is either installed
  // or downloading, never both.
  private let iconView = IconView()
  private let cancelImageView = NSImageView()
  private let chevronImageView = NSImageView()

  /// Whether the row is currently styled as downloading (in flight, paused, or in the
  /// brief post-cancel window). Set by `refresh()`; read back both to detect the
  /// cancelled transition and to gate the hover-only cancel X in `highlightDidChange`.
  private var showAsDownloading = false

  init(
    model: Model, server: LlamaServer, modelManager: ModelManager,
    actionHandler: ModelActionHandler,
    onOpen: (() -> Void)? = nil,
    showTags: Bool = false
  ) {
    self.model = model
    self.server = server
    self.modelManager = modelManager
    self.actionHandler = actionHandler
    self.onOpen = onOpen
    self.showTags = showTags
    super.init(frame: .zero)

    iconView.imageView.image =
      model.brandLogoAsset.flatMap { NSImage(named: $0) }
      ?? NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "Model")

    Theme.configure(cancelImageView, symbol: "xmark", tooltip: "Cancel download")
    cancelImageView.isHidden = true

    // Dimmed disclosure chevron -- purely decorative (the whole row is the click
    // target), so it's an image, not a button. Tertiary tint keeps it a quiet
    // hint rather than a competing accent. Shown only on installed rows.
    Theme.configure(
      chevronImageView, symbol: "chevron.right",
      color: Theme.Colors.textTertiary, pointSize: 11)
    chevronImageView.isHidden = true

    setupLayout()
    setupGestures()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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

    // Trailing accessories: the persistent chevron on installed rows and the
    // hover-only cancel X on downloading rows (see `highlightDidChange`). They
    // never show at once, so they can share the slot. Progress and pause/play
    // both live in the ring around the leading icon (see `IconView`).
    let rootStack = NSStackView(views: [leading, spacer, chevronImageView, cancelImageView])
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
    Layout.constrainToIconSize(chevronImageView)

    titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    // Allow subtitle to compress and truncate when a trailing accessory appears
    subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    cancelImageView.setContentHuggingPriority(.required, for: .horizontal)
    cancelImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
    chevronImageView.setContentHuggingPriority(.required, for: .horizontal)
    chevronImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
  }

  private func setupGestures() {
    let rowClickRecognizer = addGesture(action: #selector(didClickRow))
    rowClickRecognizer.delegate = self

    // Dedicated click target on the cancel X so paused rows can be cancelled explicitly
    // (the row body itself resumes a paused download — opposite action, same row).
    let cancelClick = NSClickGestureRecognizer(target: self, action: #selector(didClickCancel))
    cancelImageView.addGestureRecognizer(cancelClick)
  }

  @objc private func didClickRow() {
    let isInstalled = modelManager.isInstalled(model)

    if !model.isCompatible() && !isInstalled {
      NSSound.beep()
      return
    }

    if isInstalled {
      onOpen?()
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

  // Prevent row toggle when clicking the cancel X. It owns its own click
  // gesture — excluding it here stops the row-body gesture from also firing.
  // The chevron is decorative and has no gesture, so a click on it falls
  // through to the row body (opening the page) as intended.
  func gestureRecognizer(
    _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
  ) -> Bool {
    !(!cancelImageView.isHidden
      && cancelImageView.bounds.contains(cancelImageView.convert(event.locationInWindow, from: nil)))
  }

  func refresh() {
    let isActive = server.isActive(model: model)
    let isLoading = server.isLoading(model: model)
    let status = modelManager.status(for: model)

    // Derive row state from a single status switch. `fraction` drives the icon's
    // progress ring; nil means "unknown" (downloading before first response, or paused
    // with a zero total) and reads as the minimum arc. `downloadedBytes` feeds the
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

    // Only incompatible models dim the title; download state doesn't affect it.
    let isCompatible = model.isCompatible()
    let textColor = isCompatible ? Theme.Colors.textPrimary : Theme.Colors.textSecondary

    // Title is the parsed view of the id (short name + metadata chips); the
    // full raw id stays reachable via the page's copy action.
    titleLabel.attributedStringValue = Format.modelName(
      id: model.id,
      color: textColor,
      hasVision: model.hasVisionSupport,
      showTags: showTags
    )

    let incompatibility = !isCompatible ? model.incompatibilitySummary() : nil
    // Subtitle swaps between size+ctx (for installed/available rows) and a
    // transfer readout while a download is in flight: "1.2 GB of 3.1 GB", plus
    // " · Paused" when interrupted.
    // Ctx tier is only meaningful once fully downloaded, so it's omitted here.
    if showAsDownloading {
      subtitleLabel.attributedStringValue = Format.downloadSubtitle(
        downloadedBytes: downloadedBytes,
        totalBytes: model.fileSize,
        paused: isPaused
      )
    } else {
      subtitleLabel.attributedStringValue = Format.modelMetadata(
        for: model,
        incompatibility: incompatibility
      )
    }

    updateHoverAccessories()

    // While the row is styled as downloading, the leading icon swaps into its
    // downloading look: a progress ring around the rim with a pause/play glyph
    // in place of the icon (see `IconView.downloadFraction`). Keyed off
    // `showAsDownloading` (not the narrower live-or-paused state) so the icon
    // holds this look through the post-cancel flicker window too, instead of
    // popping back to the chip background for a frame before the row disappears.
    iconView.downloadFraction = showAsDownloading ? (fraction ?? 0) : nil
    iconView.downloadPaused = isPaused

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
    updateHoverAccessories()
  }

  // Keeps the trailing accessories in sync with row state: the chevron shows
  // persistently on installed rows (it opens the page), the cancel X only on
  // hovered downloading rows. Called from both `refresh()` (state changes) and
  // `highlightDidChange` (hover enters/leaves).
  private func updateHoverAccessories() {
    cancelImageView.isHidden = !(isHighlighted && showAsDownloading)
    // Installed rows navigate to the page; downloading ones don't, so suppress
    // the chevron whenever the row is styled as downloading.
    chevronImageView.isHidden = showAsDownloading || !modelManager.isInstalled(model)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .tertiaryLabelColor
  }
}
