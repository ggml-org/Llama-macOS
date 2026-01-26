import AppKit
import Foundation

/// Container view for all expanded model details.
/// Consolidates header, context variants, file size, and actions into a single view
/// with shared padding and consistent alignment.
final class ExpandedModelDetailsView: ItemView {
  private let model: CatalogEntry
  private let actionHandler: ModelActionHandler

  // Row views
  private let headerLabel = Theme.secondaryLabel()
  private let sizeLabel = Theme.secondaryLabel()
  private let actionsRow = NSStackView()

  init(model: CatalogEntry, actionHandler: ModelActionHandler) {
    self.model = model
    self.actionHandler = actionHandler
    super.init(frame: .zero)
    setupLayout()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // Disable hover highlight since this is an info container
  override var highlightEnabled: Bool { false }

  private func setupLayout() {
    // Main vertical stack for all rows
    let mainStack = NSStackView()
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.spacing = 2

    // Header row: "Context / memory usage"
    headerLabel.stringValue = "Context / memory usage"
    headerLabel.textColor = Theme.Colors.textSecondary
    mainStack.addArrangedSubview(headerLabel)

    // Context tier variant rows
    for tier in ContextTier.enabledCases {
      let row = buildVariantRow(for: tier)
      mainStack.addArrangedSubview(row)
    }

    // Spacer before file size
    let spacer1 = NSView()
    spacer1.translatesAutoresizingMaskIntoConstraints = false
    spacer1.heightAnchor.constraint(equalToConstant: 4).isActive = true
    mainStack.addArrangedSubview(spacer1)

    // File size row
    buildSizeLabel()
    mainStack.addArrangedSubview(sizeLabel)

    // Spacer before actions
    let spacer2 = NSView()
    spacer2.translatesAutoresizingMaskIntoConstraints = false
    spacer2.heightAnchor.constraint(equalToConstant: 4).isActive = true
    mainStack.addArrangedSubview(spacer2)

    // Actions row
    buildActionsRow()
    mainStack.addArrangedSubview(actionsRow)

    // Add indent wrapper to align with model text
    let indent = NSView()
    indent.translatesAutoresizingMaskIntoConstraints = false
    indent.widthAnchor.constraint(equalToConstant: Layout.expandedIndent).isActive = true

    let rootStack = NSStackView(views: [indent, mainStack])
    rootStack.orientation = .horizontal
    rootStack.alignment = .top
    rootStack.spacing = 0

    contentView.addSubview(rootStack)
    rootStack.pinToSuperview(top: 2, leading: 0, trailing: 0, bottom: 2)
  }

  // MARK: - Variant Row

  private func buildVariantRow(for tier: ContextTier) -> NSView {
    let isCompatible = model.isCompatible(ctxWindowTokens: Double(tier.rawValue))

    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 0

    let infoLabel = Theme.secondaryLabel()
    let secondaryColor = Theme.Colors.textSecondary
    let valueColor = isCompatible ? Theme.Colors.modelIconTint : Theme.Colors.textSecondary

    if isCompatible {
      let ramMb = model.runtimeMemoryUsageMb(ctxWindowTokens: Double(tier.rawValue))
      let ramGb = Double(ramMb) / 1024.0
      let ramStr = String(format: "%.1f GB", ramGb)

      // Build attributed string: "• 4k ctx  2.5 GB mem"
      let result = NSMutableAttributedString()
      let secondaryAttrs = Theme.secondaryAttributes(color: secondaryColor)
      let valueAttrs = Theme.secondaryAttributes(color: valueColor)

      result.append(NSAttributedString(string: "•  ", attributes: secondaryAttrs))
      result.append(NSAttributedString(string: tier.label, attributes: valueAttrs))
      result.append(NSAttributedString(string: " ctx  ", attributes: secondaryAttrs))
      result.append(NSAttributedString(string: ramStr, attributes: valueAttrs))
      result.append(NSAttributedString(string: " mem  ", attributes: secondaryAttrs))

      infoLabel.attributedStringValue = result

      // Copy button
      let copyButton = HoverButton()
      copyButton.title = "(copy model ID)"
      copyButton.font = Theme.Fonts.secondary
      copyButton.contentTintColor = Theme.Colors.textSecondary
      copyButton.target = self
      copyButton.action = #selector(didClickCopy(_:))
      copyButton.tag = tier.rawValue

      row.addArrangedSubview(infoLabel)
      row.addArrangedSubview(copyButton)
    } else {
      // Incompatible tier
      infoLabel.stringValue = "•  \(tier.label) ctx  not enough memory"
      infoLabel.textColor = secondaryColor
      row.addArrangedSubview(infoLabel)
    }

    return row
  }

  @objc private func didClickCopy(_ sender: NSButton) {
    guard let tier = ContextTier(rawValue: sender.tag) else { return }
    let idToCopy = "\(model.id)\(tier.suffix)"
    actionHandler.copyText(idToCopy)

    sender.title = "(copied)"
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak sender] in
      sender?.title = "(copy model ID)"
    }
  }

  // MARK: - Size Row

  private func buildSizeLabel() {
    let result = NSMutableAttributedString()
    let secondaryAttrs = Theme.secondaryAttributes(color: Theme.Colors.textSecondary)
    let valueAttrs = Theme.secondaryAttributes(color: Theme.Colors.modelIconTint)

    result.append(NSAttributedString(string: "File size  ", attributes: secondaryAttrs))
    result.append(NSAttributedString(string: model.totalSize, attributes: valueAttrs))

    sizeLabel.attributedStringValue = result
  }

  // MARK: - Actions Row

  private func buildActionsRow() {
    actionsRow.orientation = .horizontal
    actionsRow.alignment = .centerY
    actionsRow.spacing = 0

    // Show in Finder
    let showInFinderButton = HoverButton()
    showInFinderButton.title = "Show in Finder"
    showInFinderButton.font = Theme.Fonts.secondary
    showInFinderButton.contentTintColor = Theme.Colors.textSecondary
    showInFinderButton.target = self
    showInFinderButton.action = #selector(didClickShowInFinder)

    let sep = Theme.secondaryLabel()
    sep.stringValue = " · "
    sep.textColor = Theme.Colors.textSecondary

    // Delete
    let deleteButton = HoverButton()
    deleteButton.title = "Delete"
    deleteButton.font = Theme.Fonts.secondary
    deleteButton.contentTintColor = Theme.Colors.textSecondary
    deleteButton.target = self
    deleteButton.action = #selector(didClickDelete)

    actionsRow.addArrangedSubview(showInFinderButton)
    actionsRow.addArrangedSubview(sep)
    actionsRow.addArrangedSubview(deleteButton)
  }

  @objc private func didClickShowInFinder() {
    actionHandler.showInFinder(model: model)
  }

  @objc private func didClickDelete() {
    actionHandler.delete(model: model)
  }
}
