import AppKit
import Foundation

/// Container view for expanded model details.
/// Shows a compact row of context tier pills with the memory usage
/// for the selected tier. Selecting a tier updates user preferences and reloads
/// the server if running.
final class ExpandedModelDetailsView: ItemView {
  private let model: Model
  private unowned let server: LlamaServer

  // Header label
  private let headerLabel = Theme.secondaryLabel()

  // Tiers backing the picker, in the order they appear (index = segment).
  private var tiers: [ContextTier] = []
  // One pill per tier, same order as `tiers`. Each is a label wrapped in a
  // padded container whose layer draws the selection background.
  private var segments: [(container: NSView, label: NSTextField)] = []
  // Index of the currently selected tier in `tiers`.
  private var selectedIdx = 0
  // The pill row container -- outlined to give the picker a defined shape.
  private var picker: NSStackView?
  // Memory line showing the selected tier's usage (e.g. "Requires 1.6 GB of memory").
  private var memLabel: NSTextField?

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
    // Main vertical stack for indented rows
    let mainStack = NSStackView()
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.spacing = 4

    headerLabel.stringValue = "Context length"
    headerLabel.textColor = Theme.Colors.modelIconTint
    mainStack.addArrangedSubview(headerLabel)

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
      // Compact row of tier pills, plus a memory line that reflects the
      // selected tier. Custom-drawn instead of NSSegmentedControl: lighter
      // visually, and immune to the inactive-window graying AppKit applies to
      // standard controls when the app isn't frontmost (menu bar apps usually
      // aren't, so the segmented control's thumb rendered gray instead of
      // accent-colored).
      tiers = model.supportedContextTiers
      // Fall back to the first supported tier if no effective tier is resolved.
      let effectiveTier = model.effectiveCtxTier ?? tiers.first ?? .k4
      selectedIdx = tiers.firstIndex(of: effectiveTier) ?? 0

      let picker = NSStackView()
      picker.orientation = .horizontal
      picker.spacing = 2
      // Subtle outline around the whole row to give the picker a defined shape.
      picker.wantsLayer = true
      picker.layer?.borderWidth = 1
      picker.layer?.cornerRadius = 6
      picker.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
      self.picker = picker
      for (idx, tier) in tiers.enumerated() {
        picker.addArrangedSubview(makeSegment(label: tier.shortLabel, idx: idx))
      }
      restyleSegments()
      mainStack.addArrangedSubview(picker)

      let mem = Theme.secondaryLabel()
      self.memLabel = mem
      updateMemLabel(for: effectiveTier)
      mainStack.addArrangedSubview(mem)
    }

    // Add indent wrapper to align with model text
    let indent = NSView()
    indent.translatesAutoresizingMaskIntoConstraints = false
    indent.widthAnchor.constraint(equalToConstant: Layout.expandedIndent).isActive = true

    let indentedRow = NSStackView(views: [indent, mainStack])
    indentedRow.orientation = .horizontal
    indentedRow.alignment = .top
    indentedRow.spacing = 0

    contentView.addSubview(indentedRow)
    indentedRow.pinToSuperview(top: 2, leading: 0, trailing: 0, bottom: 2)

    // Pin to the standard menu width so a long label (e.g. the "Could not estimate
    // memory" fallback) can't widen the whole menu beyond what model rows use.
    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true
  }

  // MARK: - Tier Picker

  /// Creates one clickable pill for the picker: a label with a little padding
  /// in a rounded-corner container that draws the selection background.
  private func makeSegment(label text: String, idx: Int) -> NSView {
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
      label.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
    ])

    let click = NSClickGestureRecognizer(target: self, action: #selector(didClickSegment(_:)))
    container.addGestureRecognizer(click)
    segments.append((container, label))
    return container
  }

  /// Applies selected/unselected styling to every pill: the selected tier gets
  /// a subtle background and primary text, the rest plain secondary text.
  private func restyleSegments() {
    picker?.layer?.setBorderColor(Theme.Colors.separator, in: self)
    for (idx, segment) in segments.enumerated() {
      let selected = idx == selectedIdx
      segment.label.textColor = selected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary
      segment.container.layer?.setBackgroundColor(
        selected ? Theme.Colors.subtleBackground : .clear, in: self)
    }
  }

  // Layer colors are resolved CGColors, so re-resolve them when the system
  // appearance flips between light and dark.
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyleSegments()
  }

  // MARK: - Memory Line

  /// Updates the memory line to describe the usage for the given tier as a
  /// sentence (e.g. "Requires 1.6 GB of memory"). The size is omitted -- it's
  /// already shown on the selected segment -- with the figure emphasized.
  private func updateMemLabel(for tier: ContextTier) {
    guard let memLabel else { return }

    let labelColor = Theme.Colors.modelIconTint
    let valueColor = Theme.Colors.textPrimary
    let labelAttrs = Theme.secondaryAttributes(color: labelColor)
    let valueAttrs = Theme.secondaryAttributes(color: valueColor)

    let ramMb = model.runtimeMemoryUsageMb(ctxWindowTokens: Double(tier.rawValue))
    let ramGb = Double(ramMb) / 1024.0
    let ramStr = String(format: "%.1f GB", ramGb)

    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "Requires ", attributes: labelAttrs))
    result.append(NSAttributedString(string: ramStr, attributes: valueAttrs))
    result.append(NSAttributedString(string: " of memory", attributes: labelAttrs))
    memLabel.attributedStringValue = result
  }

  // MARK: - Actions

  @objc private func didClickSegment(_ sender: NSClickGestureRecognizer) {
    guard let container = sender.view,
      let idx = segments.firstIndex(where: { $0.container == container })
    else { return }
    let tier = tiers[idx]

    // Reflect the new selection in the picker and memory line right away.
    selectedIdx = idx
    restyleSegments()
    updateMemLabel(for: tier)

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
