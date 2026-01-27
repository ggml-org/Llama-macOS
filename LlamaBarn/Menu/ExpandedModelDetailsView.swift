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

  // Info block (expandable)
  private var infoButton: NSButton?
  private var infoBlock: NSView?
  private var infoExpanded = false

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
    // Outer vertical stack (holds indented content + full-width info block)
    let outerStack = NSStackView()
    outerStack.orientation = .vertical
    outerStack.alignment = .leading
    outerStack.spacing = 0

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

    headerLabel.stringValue = "Context options"
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
    headerRow.addArrangedSubview(btn)
    self.infoButton = btn

    mainStack.addArrangedSubview(headerRow)

    // Context tier variant rows - only show tiers this model supports
    for tier in model.supportedContextTiers {
      let row = buildVariantRow(for: tier)
      mainStack.addArrangedSubview(row)
    }

    // Add indent wrapper to align with model text
    let indent = NSView()
    indent.translatesAutoresizingMaskIntoConstraints = false
    indent.widthAnchor.constraint(equalToConstant: Layout.expandedIndent).isActive = true

    let indentedRow = NSStackView(views: [indent, mainStack])
    indentedRow.orientation = .horizontal
    indentedRow.alignment = .top
    indentedRow.spacing = 0

    outerStack.addArrangedSubview(indentedRow)

    // Full-width info block (outside the indent)
    let infoBlock = buildInfoBlock()
    infoBlock.isHidden = true
    outerStack.addArrangedSubview(infoBlock)
    self.infoBlock = infoBlock

    contentView.addSubview(outerStack)
    outerStack.pinToSuperview(top: 2, leading: 0, trailing: 0, bottom: 2)
  }

  // MARK: - Variant Row

  /// Builds a row for a supported context tier.
  /// Only called for tiers that are compatible with this device.
  private func buildVariantRow(for tier: ContextTier) -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 0
    // Fixed row height prevents menu resizing when expanding different models
    row.heightAnchor.constraint(equalToConstant: 16).isActive = true

    let infoLabel = Theme.secondaryLabel()
    let valueColor = Theme.Colors.textPrimary
    let labelColor = Theme.Colors.modelIconTint

    // Build attributed string
    let result = NSMutableAttributedString()
    let labelAttrs = Theme.secondaryAttributes(color: labelColor)
    let valueAttrs = Theme.secondaryAttributes(color: valueColor)

    // Status icon (checkmark for all shown tiers since they're all compatible)
    let statusIcon = NSImageView()
    Theme.configure(statusIcon, symbol: "checkmark", color: Theme.Colors.success, pointSize: 10)
    statusIcon.widthAnchor.constraint(equalToConstant: 12).isActive = true
    row.addArrangedSubview(statusIcon)

    // Spacing after icon
    let iconSpacer = NSView()
    iconSpacer.translatesAutoresizingMaskIntoConstraints = false
    iconSpacer.widthAnchor.constraint(equalToConstant: 4).isActive = true
    row.addArrangedSubview(iconSpacer)

    // Tier label and memory usage
    result.append(NSAttributedString(string: tier.label, attributes: valueAttrs))
    result.append(NSAttributedString(string: " ctx  ", attributes: labelAttrs))

    let ramMb = model.runtimeMemoryUsageMb(ctxWindowTokens: Double(tier.rawValue))
    let ramGb = Double(ramMb) / 1024.0
    let ramStr = String(format: "%.1f GB", ramGb)

    result.append(NSAttributedString(string: ramStr, attributes: valueAttrs))
    result.append(NSAttributedString(string: " mem", attributes: labelAttrs))

    infoLabel.attributedStringValue = result
    row.addArrangedSubview(infoLabel)

    // Copy button
    let copyButton = HoverButton()
    copyButton.title = "  Copy ID"
    copyButton.font = Theme.Fonts.secondary
    copyButton.contentTintColor = Theme.Colors.modelIconTint
    copyButton.target = self
    copyButton.action = #selector(didClickCopy(_:))
    copyButton.tag = tier.rawValue
    row.addArrangedSubview(copyButton)

    return row
  }

  @objc private func didClickCopy(_ sender: NSButton) {
    guard let tier = ContextTier(rawValue: sender.tag) else { return }
    let idToCopy = "\(model.id)\(tier.suffix)"
    actionHandler.copyText(idToCopy)

    sender.title = "  Copied"
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak sender] in
      sender?.title = "  Copy ID"
    }
  }

  @objc private func didClickInfo(_ sender: NSButton) {
    infoExpanded.toggle()
    infoBlock?.isHidden = !infoExpanded

    // Update button tint to indicate active state
    infoButton?.contentTintColor =
      infoExpanded
      ? Theme.Colors.textPrimary
      : Theme.Colors.textSecondary
  }

  // MARK: - Info Block

  /// Builds a full-width outlined info block explaining context options.
  private func buildInfoBlock() -> NSView {
    let paragraphs = [
      "The same model can run at multiple context lengths. Context is how much text the model can \"see\" at once.",
      "Pick 4K for chat, 32K for agents. Longer context uses more memory.",
    ]

    // Build attributed string with custom paragraph spacing
    let paraStyle = NSMutableParagraphStyle()
    paraStyle.paragraphSpacing = 6

    let attrs: [NSAttributedString.Key: Any] = [
      .font: Theme.Fonts.secondary,
      .foregroundColor: Theme.Colors.modelIconTint,
      .paragraphStyle: paraStyle,
    ]

    let result = NSMutableAttributedString()
    for (idx, para) in paragraphs.enumerated() {
      let text = idx < paragraphs.count - 1 ? para + "\n" : para
      result.append(NSAttributedString(string: text, attributes: attrs))
    }

    let label = NSTextField(labelWithAttributedString: result)
    label.isEditable = false
    label.isSelectable = false
    label.drawsBackground = false
    label.isBezeled = false
    label.lineBreakMode = .byWordWrapping
    // Content width minus indent and padding inside the box
    label.preferredMaxLayoutWidth = Layout.contentWidth - Layout.expandedIndent - 20
    label.translatesAutoresizingMaskIntoConstraints = false

    // Outlined container
    let container = NSView()
    container.wantsLayer = true
    container.layer?.cornerRadius = Layout.cornerRadius
    container.layer?.borderWidth = 1
    container.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)

    // Set border color respecting appearance
    container.layer?.setBorderColor(Theme.Colors.separator, in: container)

    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
      container.widthAnchor.constraint(
        equalToConstant: Layout.contentWidth - Layout.expandedIndent),
    ])

    // Wrapper with indent and top margin
    let indent = NSView()
    indent.translatesAutoresizingMaskIntoConstraints = false
    indent.widthAnchor.constraint(equalToConstant: Layout.expandedIndent).isActive = true

    let row = NSStackView(views: [indent, container])
    row.orientation = .horizontal
    row.alignment = .top
    row.spacing = 0

    let wrapper = NSView()
    wrapper.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(row)
    row.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 6),
      row.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
      row.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
    ])

    return wrapper
  }

}
