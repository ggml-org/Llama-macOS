import AppKit
import Foundation

/// Container view for model details.
/// Shows a compact row of context tier pills. Selecting a tier updates user
/// preferences and reloads the server if running.
final class ExpandedModelDetailsView: ItemView {
  private let model: Model
  private unowned let server: LlamaServer

  // Tiers backing the picker, in the order they appear (index = segment).
  private var tiers: [ContextTier] = []
  // Tiers actually runnable on this device; the rest render disabled.
  private var enabledTiers: Set<ContextTier> = []
  // One pill per tier, same order as `tiers`. Each is a label wrapped in a
  // padded container whose layer draws the selection background.
  private var segments: [(container: NSView, label: NSTextField)] = []
  // Hairline dividers between adjacent pills; divider[i] sits between
  // segments i and i+1. Hidden when adjacent to the selected pill.
  private var dividers: [NSView] = []
  // The projected runtime footprint for the selected tier. It lives beside the
  // context heading because memory is useful while choosing a tier, but too
  // detailed for every collapsed model row.
  private let memoryLabel = Theme.secondaryLabel()
  // Index of the currently selected tier in `tiers`.
  private var selectedIdx = 0
  // The pill row container -- outlined to give the picker a defined shape.
  private var picker: NSStackView?

  init(
    model: Model,
    server: LlamaServer,
    indented: Bool = true
  ) {
    self.model = model
    self.server = server
    super.init(frame: .zero)
    setupLayout(indented: indented)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // Disable hover highlight since this is an info container
  override var highlightEnabled: Bool { false }

  private func setupLayout(indented: Bool) {
    // Main vertical stack for indented rows
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
      // A "Context length" header with the selected tier's projected memory
      // usage beside it, then the tier pills below. Pills are custom-drawn
      // instead of NSSegmentedControl: lighter visually, and
      // immune to the inactive-window graying AppKit applies to standard
      // controls when the app isn't frontmost (menu bar apps usually aren't,
      // so the segmented control's thumb rendered gray instead of
      // accent-colored).
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
      // 1px gap on either side of each divider so the selected pill's
      // background reaches almost to the neighboring dividers.
      picker.spacing = 1
      // Subtle outline around the whole row to give the picker a defined shape.
      picker.wantsLayer = true
      picker.layer?.borderWidth = 1
      picker.layer?.cornerRadius = 6
      // 2px insets all around so the selected pill's background keeps the
      // same breathing room from the outline at the ends as it does
      // vertically.
      picker.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
      // Hug the pills tightly -- otherwise the stack stretches to the menu
      // width and the outline trails off past the last pill.
      picker.setHuggingPriority(.required, for: .horizontal)
      picker.setContentHuggingPriority(.required, for: .horizontal)
      self.picker = picker
      for (idx, tier) in tiers.enumerated() {
        if idx > 0 {
          picker.addArrangedSubview(makeDivider())
        }
        let segment = makeSegment(label: tier.shortLabel)
        // Explain why a disabled tier can't be selected (memory constraint).
        if !enabledTiers.contains(tier) {
          segment.toolTip = model.incompatibilitySummary(
            ctxWindowTokens: Double(tier.rawValue))
        }
        picker.addArrangedSubview(segment)
      }
      restyleSegments()

      let header = Theme.secondaryLabel("Context length")
      header.textColor = Theme.Colors.modelIconTint
      memoryLabel.textColor = Theme.Colors.textSecondary
      updateMemoryLabel()

      let headerRow = NSStackView(views: [header, memoryLabel])
      headerRow.orientation = .horizontal
      headerRow.alignment = .firstBaseline
      headerRow.spacing = 4
      mainStack.addArrangedSubview(headerRow)
      mainStack.addArrangedSubview(picker)
    }

    if indented {
      let indent = NSView()
      indent.translatesAutoresizingMaskIntoConstraints = false
      indent.widthAnchor.constraint(equalToConstant: Layout.expandedIndent).isActive = true

      let indentedRow = NSStackView(views: [indent, mainStack])
      indentedRow.orientation = .horizontal
      indentedRow.alignment = .top
      indentedRow.spacing = 0
      contentView.addSubview(indentedRow)
      indentedRow.pinToSuperview(top: 2, leading: 0, trailing: 0, bottom: 2)
    } else {
      contentView.addSubview(mainStack)
      mainStack.pinToSuperview(top: 4, leading: 0, trailing: 0, bottom: 6)
    }

    // Pin to the standard menu width so a long label (e.g. the "Could not estimate
    // memory" fallback) can't widen the whole menu beyond what model rows use.
    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true
  }

  // MARK: - Tier Picker

  /// Creates one clickable pill for the picker: a label with a little padding
  /// in a rounded-corner container that draws the selection background.
  private func makeSegment(label text: String) -> NSView {
    let label = Theme.secondaryLabel(text)
    let container = NSView()
    container.wantsLayer = true
    container.layer?.cornerRadius = 4
    container.translatesAutoresizingMaskIntoConstraints = false
    label.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
      label.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -1),
    ])

    let click = NSClickGestureRecognizer(target: self, action: #selector(didClickSegment(_:)))
    container.addGestureRecognizer(click)
    segments.append((container, label))
    return container
  }

  /// Creates a hairline divider that visually splits the gap between two
  /// unselected pills (the gap otherwise reads as double the edge padding).
  private func makeDivider() -> NSView {
    let divider = NSView()
    divider.wantsLayer = true
    divider.translatesAutoresizingMaskIntoConstraints = false
    divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
    divider.heightAnchor.constraint(equalToConstant: 8).isActive = true
    dividers.append(divider)
    return divider
  }

  /// Applies selected/unselected styling to every pill: the selected tier gets
  /// a subtle background and primary text, the rest plain secondary text.
  /// Also recolors the dividers, hiding those adjacent to the selection.
  private func restyleSegments() {
    picker?.layer?.setBorderColor(Theme.Colors.separator, in: self)
    for (idx, segment) in segments.enumerated() {
      let selected = idx == selectedIdx
      let enabled = enabledTiers.contains(tiers[idx])
      // Disabled tiers use the faint tertiary gray; enabled-but-unselected
      // ones use the darker icon tint (not textSecondary -- it's too close to
      // tertiary for the available/unavailable distinction to read).
      segment.label.textColor =
        !enabled
        ? Theme.Colors.textTertiary
        : selected ? Theme.Colors.textPrimary : Theme.Colors.modelIconTint
      segment.container.layer?.setBackgroundColor(
        selected ? Theme.Colors.subtleBackground : .clear, in: self)
    }
    // Hide (via clear color, to keep layout stable) the dividers touching the
    // selected pill -- its background already delimits those gaps.
    for (idx, divider) in dividers.enumerated() {
      let adjacentToSelection = idx == selectedIdx || idx + 1 == selectedIdx
      divider.layer?.setBackgroundColor(
        adjacentToSelection ? .clear : Theme.Colors.separator, in: self)
    }
  }

  /// Keeps the projected footprint synchronized with the tier selected in the
  /// picker. The estimate includes model weights and context memory.
  private func updateMemoryLabel() {
    guard tiers.indices.contains(selectedIdx) else {
      memoryLabel.stringValue = ""
      return
    }
    let tier = tiers[selectedIdx]
    let ramMb = model.runtimeMemoryUsageMb(ctxWindowTokens: Double(tier.rawValue))
    memoryLabel.stringValue = "· \(Format.memory(mb: ramMb)) memory"
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

    // Reflect the new selection and its projected footprint right away.
    selectedIdx = idx
    restyleSegments()
    updateMemoryLabel()

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
