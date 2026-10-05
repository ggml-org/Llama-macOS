import AppKit
import Foundation

/// Interactive menu item representing a single installed/downloading model.
/// Visual states:
/// - Downloading: the icon faded, its chip filling from the bottom as bytes land
/// - Installed: circular icon (inactive) + label
/// - Loading: circular icon (active, spinner)
/// - Running: circular icon (active)
///
/// The trailing slot follows the menu's existing grammar -- a persistent glyph
/// naming what clicking the row does (cf. the catalog row's download arrow and
/// `BrowseModelsRow`'s arrow.up.forward). An installed row navigates, so it
/// gets a chevron, and the page it opens owns the full action set (Chat, Copy
/// ID, Unload, Delete). A downloading row has no page worth opening -- memory
/// estimates need the file on disk -- so it stays put: clicking pauses or
/// resumes, and a pause/play glyph says so. Either way the glyph is decorative,
/// because the whole row is the click target.
///
/// Cancel is the one action that doesn't fit that scheme: a downloading row
/// genuinely has two, and nowhere to put the second. So it slides in on hover,
/// to the left of the persistent glyph -- which keeps that glyph in the same
/// column as every other row's, rather than shunting it sideways on hover.
final class ModelItemView: ItemView, NSGestureRecognizerDelegate {
  /// Point sizes for the trailing glyphs. They differ because SF Symbols fits
  /// each glyph to cap height rather than to how much of that box the mark
  /// actually fills, so equal point sizes don't read as equal: a chevron's
  /// single full-height stroke needs the least, the cancel X sits at the
  /// `Theme.configure` default, and the circled pause/play needs the most --
  /// its ring takes the height and leaves the mark inside about half of it.
  private static let chevronSize: CGFloat = 11
  private static let pausePlaySize: CGFloat = 16

  /// One box for every trailing glyph, so they all center on the same axis --
  /// with a box per glyph, the column reads ragged as rows change state. Sized
  /// for the largest of them: at `pausePlaySize` the circled pair would
  /// otherwise be scaled back down to fit `Layout.uiIconSize` and the size above
  /// cancelled out.
  private static let trailingGlyphFrame: CGFloat = 18

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

  // Icon plus the trailing glyphs: one persistent per state (chevron when
  // installed, pause/play when downloading -- mutually exclusive, so they share
  // a column) and the hover-only cancel X in its own column to their left.
  private let iconView = IconView()
  private let cancelImageView = NSImageView()
  private let chevronImageView = NSImageView()
  private let pausePlayImageView = NSImageView()

  /// Whether the row is currently styled as downloading (in flight, paused, or in the
  /// brief post-cancel window). Set by `refresh()`; read back both to detect the
  /// cancelled transition and to gate the hover-only cancel X in `highlightDidChange`.
  private var showAsDownloading = false

  /// Which of the pause/play pair is currently drawn, so `refresh()` can skip
  /// rebuilding the symbol on every progress tick. Starts matching the `pause`
  /// set up in `init`.
  private var showsPausedGlyph = false

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

    iconView.image =
      model.brandLogoAsset.flatMap { NSImage(named: $0) }
      ?? NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "Model")

    Theme.configure(cancelImageView, symbol: "xmark", tooltip: "Cancel download")
    cancelImageView.isHidden = true

    // Disclosure chevron -- purely decorative, so it takes no gesture of its own
    // and no tooltip: the whole row is the click target, and a hint on a hint
    // says nothing. Dimmer than the cancel X, which is an actual button.
    Theme.configure(
      chevronImageView, symbol: "chevron.right", color: .tertiaryLabelColor,
      pointSize: Self.chevronSize)
    chevronImageView.isHidden = true

    // Pause/play -- the downloading row's equivalent of the chevron: it names
    // the row click's outcome rather than being its own target, so like the
    // chevron it takes no gesture. Circled: a bare play triangle is near enough
    // to chevron.right that the two blur together a few rows apart in the same
    // column, and the enclosure separates them at any size. This is the only
    // place its size and tint are set; `refresh()` swaps just the symbol as the
    // state changes.
    Theme.configure(
      pausePlayImageView, symbol: "pause.circle", color: .tertiaryLabelColor,
      pointSize: Self.pausePlaySize)
    pausePlayImageView.isHidden = true

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

    // Trailing glyphs, gated in `updateTrailingGlyphs`. Cancel comes first so it
    // opens a column to the left of the persistent glyph, which stays put. The
    // chevron and pause/play never show at once, so they share the last column.
    let rootStack = NSStackView(
      views: [leading, spacer, cancelImageView, chevronImageView, pausePlayImageView])
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
    for glyph in [cancelImageView, chevronImageView, pausePlayImageView] {
      Layout.constrainToIconSize(glyph, size: Self.trailingGlyphFrame)
    }

    titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    // Allow subtitle to compress and truncate when a trailing accessory appears
    subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    cancelImageView.setContentHuggingPriority(.required, for: .horizontal)
    cancelImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
    chevronImageView.setContentHuggingPriority(.required, for: .horizontal)
    chevronImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
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

  // Prevent the row gesture from firing when the click lands on the cancel X,
  // which owns its own gesture. The chevron is decorative and deliberately
  // absent here — a click on it should fall through and open the page like the
  // rest of the row.
  func gestureRecognizer(
    _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
  ) -> Bool {
    let loc = event.locationInWindow
    return cancelImageView.isHidden
      || !cancelImageView.bounds.contains(cancelImageView.convert(loc, from: nil))
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
      hasMTP: model.hasMTPSupport,
      isDecision: model.isDecisionModel,
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
        paused: isPaused,
        bytesPerSecond: modelManager.downloadRate(for: model)
      )
    } else {
      subtitleLabel.attributedStringValue = Format.modelMetadata(
        for: model,
        incompatibility: incompatibility
      )
    }

    // Pause while in flight, play while paused -- the glyph names what a click
    // on the row would do next. Only the symbol and its tooltip vary; size and
    // tint stay with the one `Theme.configure` in `init`, so the two can't
    // drift. Guarded because `refresh()` runs on every progress tick and this
    // changes at most twice a download.
    if showsPausedGlyph != isPaused {
      showsPausedGlyph = isPaused
      pausePlayImageView.image = Theme.symbolImage(isPaused ? "play.circle" : "pause.circle")
      pausePlayImageView.toolTip = isPaused ? "Resume download" : "Pause download"
    }

    updateTrailingGlyphs()

    // While the row is styled as downloading, the leading icon swaps into its
    // downloading look: faded mark over a rising fill (see
    // `IconView.downloadFraction`). Keyed off `showAsDownloading` (not the
    // narrower live-or-paused state) so the icon holds this look through the
    // post-cancel flicker window too, instead of popping back to the chip
    // background for a frame before the row disappears.
    iconView.downloadFraction = showAsDownloading ? (fraction ?? 0) : nil

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
    updateTrailingGlyphs()
  }

  // Picks the trailing glyphs for the row's state. The persistent pair are
  // hints, not buttons, so they don't wait for hover -- a hint that appears
  // only once you're already pointing at the row is too late to be one. Cancel
  // is an actual button and stays hover-only. Called from both `refresh()`
  // (state changes while hovered) and `highlightDidChange` (hover enters/leaves).
  private func updateTrailingGlyphs() {
    cancelImageView.isHidden = !(isHighlighted && showAsDownloading)
    // Both keyed off `showAsDownloading` rather than the live-or-paused state,
    // so a cancelled row doesn't flash a chevron for a frame before it goes.
    pausePlayImageView.isHidden = !showAsDownloading
    chevronImageView.isHidden = showAsDownloading || !modelManager.isInstalled(model)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .tertiaryLabelColor
    chevronImageView.contentTintColor = .tertiaryLabelColor
    pausePlayImageView.contentTintColor = .tertiaryLabelColor
  }
}
