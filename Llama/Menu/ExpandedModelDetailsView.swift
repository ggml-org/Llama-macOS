import AppKit
import Foundation

/// Context length section of a model page.
/// Shows a full-width segmented picker where every segment pairs a tier label
/// with that tier's projected memory cost, so the context-length -> memory
/// relationship is visible at a glance without per-tier rows. Selecting a
/// tier updates user preferences and reloads the server if running.
final class ExpandedModelDetailsView: ItemView {
  private let model: Model
  private unowned let server: LlamaServer

  // Tiers backing the picker, in the order they appear (index = segment).
  private var tiers: [ContextTier] = []
  // Tiers actually runnable on this device; the rest render disabled.
  private var enabledTiers: Set<ContextTier> = []
  // One segment per tier, same order as `tiers`. Each is a two-line stack
  // (tier label over memory cost) in a padded container whose layer draws the
  // selection background.
  private var segments: [(container: NSView, name: NSTextField, cost: NSTextField)] = []
  // Hairline dividers between adjacent segments; divider[i] sits between
  // segments i and i+1. Hidden when adjacent to the selected segment.
  private var dividers: [NSView] = []
  // Index of the currently selected tier in `tiers`.
  private var selectedIdx = 0
  // The segment row container -- outlined to give the picker a defined shape.
  private var picker: NSStackView?

  init(
    model: Model,
    server: LlamaServer
  ) {
    self.model = model
    self.server = server
    super.init(frame: .zero)
    setupLayout()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // Disable hover highlight since this is an info container
  override var highlightEnabled: Bool { false }

  private func setupLayout() {
    let mainStack = NSStackView()
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.spacing = 4

    // For sideloaded models awaiting their MemProfile, show a placeholder message
    // instead of the picker (we don't have accurate memory estimates yet).
    // For failed estimation (-1), show a failure message with the 4k fallback.
    if model.ctxBytesPer1kTokens == 0 {
      let estimatingLabel = Theme.secondaryLabel()
      estimatingLabel.stringValue = "Estimating memory requirements..."
      estimatingLabel.textColor = Theme.Colors.textSecondary
      mainStack.addArrangedSubview(estimatingLabel)
    } else if model.ctxBytesPer1kTokens < 0 {
      let failedLabel = Theme.secondaryLabel()
      failedLabel.stringValue = "Could not estimate memory — using 4k context"
      failedLabel.textColor = Theme.Colors.textSecondary
      failedLabel.maximumNumberOfLines = 1
      failedLabel.lineBreakMode = .byTruncatingTail
      mainStack.addArrangedSubview(failedLabel)
    } else {
      // A "Context length" header, then the two-line segments below (tier
      // label over its projected memory cost, so each segment self-describes
      // the context -> memory tradeoff). Segments are custom-drawn instead
      // of NSSegmentedControl: lighter visually, and immune to the
      // inactive-window graying AppKit applies to standard controls when the
      // app isn't frontmost (menu bar apps usually aren't).
      // Show every tier the model natively supports; the ones this device
      // can't fit in memory render disabled so the model's full range is
      // still visible.
      tiers = model.displayContextTiers
      enabledTiers = Set(model.supportedContextTiers)
      // Fall back to the first supported tier if no effective tier is resolved.
      let effectiveTier = model.effectiveCtxTier ?? tiers.first ?? .k4
      selectedIdx = tiers.firstIndex(of: effectiveTier) ?? 0

      let picker = NSStackView()
      picker.orientation = .horizontal
      // 1px gap on either side of each divider so the selected segment's
      // background reaches almost to the neighboring dividers.
      picker.spacing = 1
      picker.distribution = .fillEqually
      // Subtle outline around the whole row to give the picker a defined shape.
      picker.wantsLayer = true
      picker.layer?.borderWidth = 1
      picker.layer?.cornerRadius = 6
      // 2px insets all around so the selected segment's background keeps the
      // same breathing room from the outline at the ends as it does
      // vertically.
      picker.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
      self.picker = picker
      for (idx, tier) in tiers.enumerated() {
        if idx > 0 {
          picker.addArrangedSubview(makeDivider())
        }
        let segment = makeSegment(tier: tier)
        // Enabled tiers show their memory cost inline (see the sublabel in
        // `makeSegment`), so they need no tooltip. Disabled tiers still get one
        // to explain why they can't be selected -- info shown nowhere else.
        if !enabledTiers.contains(tier) {
          segment.toolTip = model.incompatibilitySummary(
            ctxWindowTokens: Double(tier.rawValue))
        }
        picker.addArrangedSubview(segment)
      }
      restyleSegments()

      // The header doubles as a legend for each segment's two lines: "Context
      // length" in the tier labels' tint, "memory use" dimmer like the cost
      // sublabels, so the word-to-line pairing carries the meaning without a
      // separate caption.
      let header = Theme.secondaryLabel()
      let headerText = NSMutableAttributedString(
        string: "Context length",
        attributes: [
          .font: Theme.Fonts.secondary,
          .foregroundColor: Theme.Colors.modelIconTint,
        ])
      headerText.append(NSAttributedString(
        string: " · memory use",
        attributes: [
          .font: Theme.Fonts.secondary,
          .foregroundColor: Theme.Colors.textTertiary,
        ]))
      header.attributedStringValue = headerText
      mainStack.addArrangedSubview(header)
      mainStack.addArrangedSubview(picker)
      // The picker spans the full content width, with segments sharing it
      // equally (fillEqually above) so the costs read as a table column.
      picker.widthAnchor.constraint(equalToConstant: Layout.contentWidth).isActive = true

      // One caption explaining every dimmed segment, in place of per-segment
      // tooltips as the primary explanation (tooltips remain for the numbers).
      if enabledTiers.count < tiers.count {
        let caption = Theme.tertiaryLabel("Dimmed sizes need more memory than this Mac has")
        caption.maximumNumberOfLines = 1
        caption.lineBreakMode = .byTruncatingTail
        mainStack.addArrangedSubview(caption)
      }
    }

    contentView.addSubview(mainStack)
    mainStack.pinToSuperview(top: 4, leading: 0, trailing: 0, bottom: 6)

    // Pin to the standard menu width so a long label (e.g. the "Could not estimate
    // memory" fallback) can't widen the whole menu beyond what model rows use.
    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true
  }

  // MARK: - Tier Picker

  /// The segment sublabel: this tier's projected memory. One decimal under
  /// 10 GB, whole numbers above -- the decimal stops being meaningful and the
  /// narrow form keeps 7-tier pickers within the menu width.
  private func costLabel(for tier: ContextTier) -> String {
    let mb = model.runtimeMemoryUsageMb(ctxWindowTokens: Double(tier.rawValue))
    let gb = Double(mb) / 1024.0
    let number = gb < 10 ? String(format: "%.1f", gb) : String(format: "%.0f", gb.rounded())
    return number + " GB"
  }

  /// Creates one clickable segment: the tier label over its memory cost,
  /// centered in a rounded-corner container that draws the selection
  /// background.
  private func makeSegment(tier: ContextTier) -> NSView {
    let name = Theme.secondaryLabel(tier.shortLabel)
    let cost = Theme.secondaryLabel(costLabel(for: tier))
    // A step smaller than the tier label so the cost reads as its sublabel.
    cost.font = NSFont.systemFont(ofSize: 9)

    let column = NSStackView(views: [name, cost])
    column.orientation = .vertical
    column.alignment = .centerX
    column.spacing = 0

    let container = NSView()
    container.wantsLayer = true
    container.layer?.cornerRadius = 4
    container.translatesAutoresizingMaskIntoConstraints = false
    column.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(column)
    NSLayoutConstraint.activate([
      column.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      // Keep the two-line column from widening a segment past its equal share.
      column.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
      column.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
      column.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
    ])

    let click = NSClickGestureRecognizer(target: self, action: #selector(didClickSegment(_:)))
    container.addGestureRecognizer(click)
    segments.append((container, name, cost))
    return container
  }

  /// Creates a hairline divider that visually splits the gap between two
  /// unselected segments (the gap otherwise reads as double the edge padding).
  private func makeDivider() -> NSView {
    let divider = NSView()
    divider.wantsLayer = true
    divider.translatesAutoresizingMaskIntoConstraints = false
    divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
    divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
    dividers.append(divider)
    return divider
  }

  /// Applies selected/unselected styling to every segment: the selected tier
  /// gets a subtle background and primary text, the rest plain secondary text.
  /// Also recolors the dividers, hiding those adjacent to the selection.
  private func restyleSegments() {
    picker?.layer?.setBorderColor(Theme.Colors.separator, in: self)
    for (idx, segment) in segments.enumerated() {
      let selected = idx == selectedIdx
      let enabled = enabledTiers.contains(tiers[idx])
      // Disabled tiers use the faint tertiary gray; enabled-but-unselected
      // ones use the darker icon tint (not textSecondary -- it's too close to
      // tertiary for the available/unavailable distinction to read).
      segment.name.textColor =
        !enabled
        ? Theme.Colors.textTertiary
        : selected ? Theme.Colors.textPrimary : Theme.Colors.modelIconTint
      // The cost line always sits one visual step below its tier label so the
      // tier stays the anchor of each segment.
      segment.cost.textColor =
        !enabled
        ? Theme.Colors.textTertiary
        : selected ? Theme.Colors.textSecondary : Theme.Colors.textTertiary
      segment.container.layer?.setBackgroundColor(
        selected ? Theme.Colors.subtleBackground : .clear, in: self)
    }
    // Hide (via clear color, to keep layout stable) the dividers touching the
    // selected segment -- its background already delimits those gaps.
    for (idx, divider) in dividers.enumerated() {
      let adjacentToSelection = idx == selectedIdx || idx + 1 == selectedIdx
      divider.layer?.setBackgroundColor(
        adjacentToSelection ? .clear : Theme.Colors.separator, in: self)
    }
  }

  // Layer colors are resolved CGColors, so re-resolve them when the system
  // appearance flips between light and dark.
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyleSegments()
  }

  // MARK: - Actions

  @objc private func didClickSegment(_ sender: NSClickGestureRecognizer) {
    guard let container = sender.view,
      let idx = segments.firstIndex(where: { $0.container == container })
    else { return }
    let tier = tiers[idx]

    // Ignore clicks on tiers this device can't run.
    guard enabledTiers.contains(tier) else { return }

    // Reflect the new selection right away.
    selectedIdx = idx
    restyleSegments()

    // Skip the rest if this is already the active tier.
    guard tier != model.effectiveCtxTier else { return }

    // Save the new preference
    UserSettings.setSelectedCtxTier(tier, for: model.id)

    // Regenerate models.ini and reload server
    ModelManager.shared.updateModelsFile()

    // If this model is running, restart the server to apply the new context size
    if server.isActive(model: model) {
      server.reload()
    }
  }

}
