import AppKit
import Foundation

final class VariantItemView: ItemView {
  private let model: CatalogEntry
  private let tier: ContextTier
  private let isLoaded: Bool
  private let isCompatible: Bool
  private let copyAction: (String) -> Void

  private let leadingLabel = Theme.secondaryLabel()
  private let memoryLabel = Theme.secondaryLabel()
  private let statusLabel = Theme.secondaryLabel()
  private let copyButton = NSButton()

  private var showingCopyConfirmation = false

  init(
    model: CatalogEntry,
    tier: ContextTier,
    isLoaded: Bool,
    copyAction: @escaping (String) -> Void
  ) {
    self.model = model
    self.tier = tier
    self.isLoaded = isLoaded
    self.copyAction = copyAction

    // Check compatibility for this specific tier
    // Note: We use Double(tier.rawValue) for token count
    self.isCompatible = model.isCompatible(ctxWindowTokens: Double(tier.rawValue))

    super.init(frame: .zero)
    setupLayout()
    configureViews()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 32) }

  private func setupLayout() {
    // Layout:  [Indent] [4k] ... [Memory] [Copy] [Status] [Padding]

    // Indent (match model icon center roughly)
    let indent = NSView()
    indent.widthAnchor.constraint(equalToConstant: 44).isActive = true

    // Context Label (fixed width for alignment)
    leadingLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
    leadingLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    // Middle Spacer
    let spacer = NSView()

    let stack = NSStackView(views: [indent, leadingLabel, memoryLabel, copyButton, statusLabel])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 12

    // Add spacer after memory label manually via stack distribution or by inserting it
    stack.removeView(copyButton)
    stack.removeView(statusLabel)
    stack.addArrangedSubview(spacer)
    stack.addArrangedSubview(copyButton)
    stack.addArrangedSubview(statusLabel)

    // Ensure spacer pushes content
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

    contentView.addSubview(stack)
    stack.pinToSuperview(top: 0, leading: 10, trailing: 16, bottom: 0)

    Theme.configure(copyButton, symbol: "doc.on.doc", tooltip: "Copy ID with context suffix")
    copyButton.target = self
    copyButton.action = #selector(didClickCopy)
    Layout.constrainToIconSize(copyButton)
  }

  private func configureViews() {
    leadingLabel.stringValue = tier.label

    if isCompatible {
      let ramBytes = model.runtimeMemoryUsageMb(ctxWindowTokens: Double(tier.rawValue))
      // runtimeMemoryUsageMb returns MB (UInt64), Format.memory checks bytes usually?
      // model.runtimeMemoryUsageMb returns MB.
      // Let's format it.
      let ramGb = Double(ramBytes) / 1024.0
      memoryLabel.stringValue = String(format: "~%.1f GB", ramGb)

      copyButton.isHidden = false

      if isLoaded {
        statusLabel.stringValue = "● loaded"
        statusLabel.textColor = .systemGreen
      } else {
        statusLabel.stringValue = ""
      }
    } else {
      memoryLabel.stringValue = "not enough memory"
      copyButton.isHidden = true
      statusLabel.stringValue = ""
    }

    let color = isCompatible ? Theme.Colors.textSecondary : NSColor.disabledControlTextColor
    leadingLabel.textColor = color
    memoryLabel.textColor = color
  }

  @objc private func didClickCopy() {
    // Format: id:suffix (e.g. model:32k)
    // For 4k, RFC says "Base ID defaults to 4k".
    // But "Copy button ... copy the model ID (e.g., qwen3-coder-32b:32k)"
    // If I select 4k, should I copy base ID or :4k?
    // "No magic rounding — explicit is better".
    // "Requesting a variant that doesn't exist ... returns not found".
    // If I copy the ID, explicit is safer.

    let idToCopy = "\(model.id)\(tier.suffix)"
    copyAction(idToCopy)

    showingCopyConfirmation = true
    Theme.updateCopyIcon(copyButton, showingConfirmation: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self else { return }
      self.showingCopyConfirmation = false
      Theme.updateCopyIcon(self.copyButton, showingConfirmation: false)
    }
  }
}
