import AppKit
import Foundation

/// Container view for expanded model details.
/// Shows selectable context tiers with memory usage.
/// Selecting a tier updates user preferences and reloads the server if running.
final class ExpandedModelDetailsView: ItemView {
  private let model: CatalogEntry
  private let actionHandler: ModelActionHandler
  private unowned let server: LlamaServer

  // Header label
  private let headerLabel = Theme.secondaryLabel()

  // Info label (replaces button when expanded)
  private var infoLabel: NSTextField?
  private var infoButton: NSButton?
  private var infoExpanded: Bool
  private let onInfoToggle: ((Bool) -> Void)?

  init(
    model: CatalogEntry,
    actionHandler: ModelActionHandler,
    server: LlamaServer,
    isInfoExpanded: Bool = false,
    onInfoToggle: ((Bool) -> Void)? = nil
  ) {
    self.model = model
    self.actionHandler = actionHandler
    self.server = server
    self.infoExpanded = isInfoExpanded
    self.onInfoToggle = onInfoToggle
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
    mainStack.spacing = 2

    // Header row with info button
    let headerRow = NSStackView()
    headerRow.orientation = .horizontal
    headerRow.alignment = .centerY
    headerRow.spacing = 4
    headerRow.detachesHiddenViews = true  // Hidden views don't take up space

    headerLabel.stringValue = "Context length"
    headerLabel.textColor = Theme.Colors.modelIconTint
    headerRow.addArrangedSubview(headerLabel)

    // Info button toggles explanation text
    let btn = NSButton()
    btn.bezelStyle = .inline
    btn.isBordered = false
    btn.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Info")
    btn.imagePosition = .imageOnly
    btn.contentTintColor = Theme.Colors.textSecondary
    btn.target = self
    btn.action = #selector(didClickInfo(_:))
    btn.isHidden = infoExpanded  // Hide if already expanded
    self.infoButton = btn
    headerRow.addArrangedSubview(btn)

    // Info label (hidden by default, shows inline with header)
    let info = Theme.secondaryLabel()
    info.stringValue =
      "Context length — how far back the model can see. Larger values use more memory."
    info.textColor = Theme.Colors.modelIconTint
    info.lineBreakMode = .byWordWrapping
    info.isHidden = !infoExpanded  // Show if already expanded
    // Constrain width to prevent unbounded height calculation
    info.preferredMaxLayoutWidth = Layout.contentWidth - Layout.expandedIndent
    self.infoLabel = info
    headerRow.addArrangedSubview(info)

    // Apply initial state
    headerLabel.isHidden = infoExpanded

    mainStack.addArrangedSubview(headerRow)

    // For sideloaded models awaiting fit-params, show a placeholder message
    // instead of tier rows (we don't have accurate memory estimates yet).
    // For failed estimation (-1), show a failure message with the 4k fallback.
    if model.isSideloaded && model.ctxBytesPer1kTokens == 0 {
      let estimatingLabel = Theme.secondaryLabel()
      estimatingLabel.stringValue = "Estimating memory requirements..."
      estimatingLabel.textColor = Theme.Colors.textSecondary
      mainStack.addArrangedSubview(estimatingLabel)
    } else if model.isSideloaded && model.ctxBytesPer1kTokens < 0 {
      let failedLabel = Theme.secondaryLabel()
      failedLabel.stringValue = "Could not estimate memory — using 4k context"
      failedLabel.textColor = Theme.Colors.textSecondary
      mainStack.addArrangedSubview(failedLabel)
    } else {
      // Context tier rows - show all supported tiers as selectable options
      let effectiveTier = model.effectiveCtxTier
      for tier in model.supportedContextTiers {
        let isSelected = tier == effectiveTier
        let row = buildTierRow(for: tier, isSelected: isSelected)
        mainStack.addArrangedSubview(row)
      }
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
  }

  // MARK: - Tier Row

  /// Builds a selectable row for a context tier.
  private func buildTierRow(for tier: ContextTier, isSelected: Bool) -> NSView {
    // Use a custom view subclass to store the tier value
    let row = TierRowView(tier: tier)
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 0
    // Fixed row height prevents menu resizing when expanding different models
    row.heightAnchor.constraint(equalToConstant: 16).isActive = true

    let infoLabel = Theme.secondaryLabel()
    let labelColor = Theme.Colors.modelIconTint
    let valueColor = Theme.Colors.textPrimary

    // Build attributed string
    let result = NSMutableAttributedString()
    let labelAttrs = Theme.secondaryAttributes(color: labelColor)
    let valueAttrs = Theme.secondaryAttributes(color: valueColor)

    // Selection indicator (small filled circle inside ring for selected, empty circle for others)
    let statusIcon = NSImageView()
    if isSelected {
      Theme.configure(
        statusIcon, symbol: "smallcircle.filled.circle", color: Theme.Colors.textPrimary,
        pointSize: 10)
    } else {
      Theme.configure(
        statusIcon, symbol: "circle", color: Theme.Colors.textSecondary, pointSize: 10)
    }
    statusIcon.widthAnchor.constraint(equalToConstant: 12).isActive = true
    row.addArrangedSubview(statusIcon)

    // Spacing after icon
    let iconSpacer = NSView()
    iconSpacer.translatesAutoresizingMaskIntoConstraints = false
    iconSpacer.widthAnchor.constraint(equalToConstant: 4).isActive = true
    row.addArrangedSubview(iconSpacer)

    // Tier label and memory usage
    result.append(NSAttributedString(string: tier.label, attributes: valueAttrs))
    result.append(NSAttributedString(string: " on ", attributes: labelAttrs))

    let ramMb = model.runtimeMemoryUsageMb(ctxWindowTokens: Double(tier.rawValue))
    let ramGb = Double(ramMb) / 1024.0
    let ramStr = String(format: "%.1f GB", ramGb)

    result.append(NSAttributedString(string: ramStr, attributes: valueAttrs))
    result.append(NSAttributedString(string: " mem", attributes: labelAttrs))

    infoLabel.attributedStringValue = result
    row.addArrangedSubview(infoLabel)

    // Make the row clickable to select this tier
    let clickRecognizer = NSClickGestureRecognizer(
      target: self, action: #selector(didClickTierRow(_:)))
    row.addGestureRecognizer(clickRecognizer)

    return row
  }

  @objc private func didClickTierRow(_ sender: NSClickGestureRecognizer) {
    guard let row = sender.view as? TierRowView else { return }
    let tier = row.tier

    // Skip if already selected
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

  @objc private func didClickInfo(_ sender: NSButton) {
    infoExpanded.toggle()
    headerLabel.isHidden = infoExpanded
    infoLabel?.isHidden = !infoExpanded
    infoButton?.isHidden = infoExpanded
    onInfoToggle?(infoExpanded)
  }

}

// MARK: - TierRowView

/// Custom stack view that stores a context tier value.
/// Used to pass tier info through gesture recognizer callbacks.
private final class TierRowView: NSStackView {
  let tier: ContextTier

  init(tier: ContextTier) {
    self.tier = tier
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
