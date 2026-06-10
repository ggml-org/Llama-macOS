import AppKit
import Foundation

/// Container view for expanded model details.
/// Shows a compact segmented control of context tiers with the memory usage
/// for the selected tier. Selecting a tier updates user preferences and reloads
/// the server if running.
final class ExpandedModelDetailsView: ItemView {
  private let model: Model
  private unowned let server: LlamaServer

  // Header label
  private let headerLabel = Theme.secondaryLabel()

  // Tiers backing the segmented control, in the order they appear (index = segment).
  private var tiers: [ContextTier] = []
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
      // Compact segmented control of supported tiers, plus a memory line that
      // reflects the selected tier.
      tiers = model.supportedContextTiers
      // Fall back to the first supported tier if no effective tier is resolved.
      let effectiveTier = model.effectiveCtxTier ?? tiers.first ?? .k4

      let segmented = NSSegmentedControl(
        labels: tiers.map { $0.shortLabel },
        trackingMode: .selectOne,
        target: self,
        action: #selector(didSelectSegment(_:)))
      segmented.segmentStyle = .rounded
      segmented.controlSize = .small
      segmented.font = Theme.Fonts.secondary
      if let idx = tiers.firstIndex(of: effectiveTier) {
        segmented.selectedSegment = idx
      }
      mainStack.addArrangedSubview(segmented)

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

  @objc private func didSelectSegment(_ sender: NSSegmentedControl) {
    let idx = sender.selectedSegment
    guard idx >= 0, idx < tiers.count else { return }
    let tier = tiers[idx]

    // Reflect the new selection in the memory line right away.
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
