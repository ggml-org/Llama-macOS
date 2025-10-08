import AppKit
import Foundation

/// Interactive menu item that triggers a submenu for a model family, showing model size indicators with download/compatibility status.
///
/// Background and hover handling provided by ItemView.
/// Size indicators are rebuilt on each refresh rather than tracked statefully for simplicity.
final class FamilyItemView: ItemView {
  // MARK: - Properties

  private let family: String
  private let sortedModels: [CatalogEntry]
  private unowned let modelManager: ModelManager

  private let iconView = IconBadgeView(cornerStyle: .rounded)
  private let familyLabel = Typography.makePrimaryLabel()
  private let metadataLabel = Typography.makeSecondaryLabel()
  private let chevron = NSImageView()

  // MARK: - Initialization

  init(family: String, sortedModels: [CatalogEntry], modelManager: ModelManager) {
    self.family = family
    self.sortedModels = sortedModels
    self.modelManager = modelManager
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 40) }

  // MARK: - Setup

  /// Configures the view hierarchy and layout constraints.
  private func setup() {
    wantsLayer = true

    // Configure icon view
    iconView.setImage(NSImage(named: sortedModels.first?.icon ?? ""))

    // Configure family name label
    familyLabel.stringValue = family

    // Configure metadata label (second line showing all available model sizes)
    // Contains all size entries in a single attributed string (e.g., "✓ 270M • 1B • ✓ 4B • 12B")

    // Configure chevron indicator
    chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    // Match InstalledModelMenuItemView trailing indicator sizing for alignment.
    chevron.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    chevron.contentTintColor = Typography.primaryColor

    // Build layout hierarchy: icon + text column on left, chevron on right
    let textColumn = NSStackView(views: [familyLabel, metadataLabel])
    textColumn.orientation = .vertical
    textColumn.spacing = 2
    textColumn.alignment = .leading

    // Center icon vertically against two-line text to match InstalledModelMenuItemView layout.
    let leadingStack = NSStackView(views: [iconView, textColumn])
    leadingStack.orientation = .horizontal
    leadingStack.spacing = 6
    leadingStack.alignment = .centerY

    // Main row with flexible space between leading content and chevron
    let hStack = NSStackView(views: [leadingStack, NSView(), chevron])
    hStack.translatesAutoresizingMaskIntoConstraints = false
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY

    contentView.addSubview(hStack)

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: Layout.iconBadgeSize),
      iconView.heightAnchor.constraint(equalToConstant: Layout.iconBadgeSize),
      chevron.widthAnchor.constraint(equalToConstant: Layout.iconSize),
      chevron.heightAnchor.constraint(equalToConstant: Layout.iconSize),
      hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      hStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  // MARK: - Refresh

  /// Updates the metadata line with current model size states.
  func refresh() {
    metadataLabel.attributedStringValue = makeMetadataLine()
    needsDisplay = true
  }

  // MARK: - Metadata Line Construction

  /// Builds an attributed string showing each unique model build in this family,
  /// highlighting downloads with a checkmark.
  private func makeMetadataLine() -> NSAttributedString {
    // Deduplicate by the underlying build so separate quantized entries remain visible once.
    var used: Set<String> = []
    let line = NSMutableAttributedString()

    for model in sortedModels {
      guard used.insert(model.id).inserted else { continue }

      let status = modelManager.status(for: model)
      let downloaded = (status == .installed)

      // Add separator between entries
      if line.length > 0 {
        line.append(MetadataLabel.makeSeparator())
      }

      line.append(attributedSizeLabel(for: model, downloaded: downloaded))
    }

    return line
  }

  /// Creates an attributed string for a model size label.
  /// Downloaded models show a checkmark to indicate they're already installed.
  /// Unsupported models use a dimmed tertiary label color.
  private func attributedSizeLabel(
    for model: CatalogEntry,
    downloaded: Bool
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    // Add checkmark for downloaded models
    if downloaded {
      result.append(MetadataLabel.makeIconOnly(icon: Symbols.checkmark))
      result.append(NSAttributedString(string: " "))
    }

    // Build size text (e.g., "27B" or "27B-Q4")
    let quantSuffix =
      model.isFullPrecision ? "" : "-" + QuantizationFormatters.short(model.quantization)
    let sizeText = "\(model.size)\(quantSuffix)"

    // Use tertiary color for unsupported models
    let isSupported = Catalog.isModelCompatible(model)
    let textColor: NSColor = isSupported ? Typography.secondaryColor : Typography.tertiaryColor

    result.append(
      NSAttributedString(
        string: sizeText,
        attributes: [
          .font: Typography.secondary,
          .foregroundColor: textColor,
        ]
      ))
    return result
  }
}
