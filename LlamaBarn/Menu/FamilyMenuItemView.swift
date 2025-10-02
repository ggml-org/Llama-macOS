import AppKit
import Foundation

/// Interactive menu item that triggers a submenu for a model family, showing model size indicators with download/compatibility status.
final class FamilyMenuItemView: MenuItemView {
  private let family: String
  private let models: [CatalogEntry]
  private unowned let modelManager: Manager

  private let iconView = RoundedRectIconView()
  private let familyLabel = NSTextField(labelWithString: "")
  private let metadataLabel = NSTextField(labelWithString: "")
  private let chevron = NSImageView()
  // Background and hover handling provided by MenuItemView.
  // Size indicators are rebuilt on each refresh rather than tracked statefully for simplicity.

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
    // Family rows trigger submenus rather than actions, so never show active state.
    iconView.isActive = false

    familyLabel.stringValue = family
    familyLabel.font = Typography.primary
    familyLabel.translatesAutoresizingMaskIntoConstraints = false

    metadataLabel.font = Typography.secondary
    metadataLabel.textColor = .secondaryLabelColor
    metadataLabel.lineBreakMode = .byTruncatingTail
    metadataLabel.translatesAutoresizingMaskIntoConstraints = false

    chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    // Match InstalledModelMenuItemView trailing indicator sizing for alignment.
    chevron.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    chevron.contentTintColor = .secondaryLabelColor
    chevron.translatesAutoresizingMaskIntoConstraints = false

    let textColumn = NSStackView(views: [familyLabel, metadataLabel])
    textColumn.orientation = .vertical
    textColumn.spacing = 2
    textColumn.alignment = .leading
    textColumn.translatesAutoresizingMaskIntoConstraints = false

    // Center icon vertically against two-line text to match InstalledModelMenuItemView layout.
    let leadingStack = NSStackView(views: [iconView, textColumn])
    leadingStack.orientation = .horizontal
    leadingStack.spacing = 6
    leadingStack.alignment = .centerY
    leadingStack.translatesAutoresizingMaskIntoConstraints = false

    let hStack = NSStackView(views: [leadingStack, NSView(), chevron])
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY
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

  func refresh() {
    metadataLabel.attributedStringValue = makeMetadataLine()
    needsDisplay = true
  }

  private func makeMetadataLine() -> NSAttributedString {
    let sorted = models.sorted(by: CatalogEntry.displayOrder(_:_:))
    // Deduplicate sizes since multiple builds can share the same size.
    var used: Set<String> = []
    let line = NSMutableAttributedString()

    for model in sorted {
      if used.contains(model.size) { continue }
      used.insert(model.size)

      let status = modelManager.getModelStatus(model)
      let downloaded = (status == .downloaded)
      let compatible = Catalog.isModelCompatible(model)
      let color: NSColor = (downloaded || compatible) ? .labelColor : .secondaryLabelColor
      if line.length > 0 {
        line.append(MetadataSeparator.make(color: color))
      }

      line.append(attributedSizeLabel(text: model.size, downloaded: downloaded, color: color))
    }

    return line
  }

  private func attributedSizeLabel(
    text: String,
    downloaded: Bool,
    color: NSColor
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    if downloaded {
      result.append(
        MetadataLabel.makeIconOnly(
          icon: MetadataIcons.checkSymbol,
          color: .llamaGreen,
          baselineOffset: MetadataIcons.checkBaselineOffset
        )
      )
      result.append(NSAttributedString(string: " "))
    }

    result.append(
      NSAttributedString(
        string: text,
        attributes: [
          .font: Typography.secondary,
          .foregroundColor: color,
        ]
      )
    )

    return result
  }
}
