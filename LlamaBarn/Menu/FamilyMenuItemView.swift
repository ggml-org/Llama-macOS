import AppKit
import Foundation

/// Displays a model family with variant badges summarizing status.
final class FamilyMenuItemView: MenuRowView {
  private let family: String
  private let models: [CatalogEntry]
  private unowned let modelManager: Manager

  private let iconView = RoundedRectIconView()
  private let familyLabel = NSTextField(labelWithString: "")
  private let metadataLabel = NSTextField(labelWithString: "")
  private let chevron = NSImageView()
  // Background is provided by MenuRowView
  // No stateful map needed; we rebuild badges each refresh for clarity.

  // Hover handling provided by MenuRowView

  init(family: String, models: [CatalogEntry], modelManager: Manager) {
    self.family = family
    self.models = models
    self.modelManager = modelManager
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 40) }

  private func setup() {
    wantsLayer = true
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.setImage(NSImage(named: models.first?.icon ?? ""))
    // Family rows never become "active" blue; keep inactive style always.
    iconView.isActive = false

    familyLabel.stringValue = family
    // Match primary row font size used elsewhere (Installed models, server status, catalog entries)
    familyLabel.font = Typography.primary
    familyLabel.translatesAutoresizingMaskIntoConstraints = false

    metadataLabel.font = Typography.secondary
    metadataLabel.textColor = .secondaryLabelColor
    metadataLabel.lineBreakMode = .byTruncatingTail
    metadataLabel.translatesAutoresizingMaskIntoConstraints = false

    chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    // Match trailing indicator sizing (16x16 w/ pointSize 14) used in InstalledModelMenuItemView for alignment
    chevron.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    chevron.contentTintColor = .secondaryLabelColor
    chevron.translatesAutoresizingMaskIntoConstraints = false

    let textColumn = NSStackView(views: [familyLabel, metadataLabel])
    textColumn.orientation = .vertical
    // Use same vertical spacing as other two-line rows for visual consistency
    textColumn.spacing = 2
    textColumn.alignment = .leading
    textColumn.translatesAutoresizingMaskIntoConstraints = false

    // Nest icon + text column so we can align icon with first line (family label) instead of vertical center.
    let leadingStack = NSStackView(views: [iconView, textColumn])
    leadingStack.orientation = .horizontal
    leadingStack.spacing = 6
    // Match InstalledModelMenuItemView: vertically center circular badge relative to two-line text.
    leadingStack.alignment = .centerY
    leadingStack.translatesAutoresizingMaskIntoConstraints = false

    let hStack = NSStackView(views: [leadingStack, NSView(), chevron])
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY  // overall row still vertically centered in its container
    hStack.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(hStack)

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      iconView.heightAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      chevron.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
      chevron.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
      hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      hStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }
  // No hover tint change for the header icon; keep consistent.

  func refresh() {
    metadataLabel.attributedStringValue = makeMetadataLine()
    needsDisplay = true
  }

  private func makeMetadataLine() -> NSAttributedString {
    let sorted = models.sorted(by: CatalogEntry.displayOrder(_:_:))
    var used: Set<String> = []
    let line = NSMutableAttributedString()

    for model in sorted {
      if used.contains(model.variant) { continue }
      used.insert(model.variant)

      let status = modelManager.getModelStatus(model)
      let downloaded = (status == .downloaded)
      let compatible = Catalog.isModelCompatible(model)
      let color: NSColor = (downloaded || compatible) ? .labelColor : .secondaryLabelColor
      if line.length > 0 {
        line.append(MetadataSeparator.make(color: color))
      }

      line.append(attributedVariantLabel(text: model.variant, downloaded: downloaded, color: color))
    }

    return line
  }

  private func attributedVariantLabel(
    text: String,
    downloaded: Bool,
    color: NSColor
  ) -> NSAttributedString {
    if downloaded {
      let result = NSMutableAttributedString()
      result.append(
        IconLabelFormatter.makeIconOnly(
          icon: MetadataIcons.checkSymbol,
          color: .llamaGreen,
          baselineOffset: MetadataIcons.checkBaselineOffset
        )
      )
      result.append(
        NSAttributedString(
          string: " \(text)",
          attributes: [
            .font: Typography.secondary,
            .foregroundColor: color,
          ]
        )
      )
      return result
    }

    return NSAttributedString(
      string: text,
      attributes: [
        .font: Typography.secondary,
        .foregroundColor: color,
      ]
    )
  }
}
