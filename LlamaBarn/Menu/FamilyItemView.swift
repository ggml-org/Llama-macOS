import AppKit

/// Interactive menu item that expands/collapses to show models in a family inline.
///
/// Background and hover handling provided by ItemView.
/// Size indicators are rebuilt on each refresh rather than tracked statefully for simplicity.
final class FamilyItemView: ItemView {
  // MARK: - Properties

  private let family: String
  private let sortedModels: [CatalogEntry]
  private unowned let modelManager: ModelManager
  private let onToggle: (String) -> Void
  private var isExpanded: Bool

  private let familyLabel = Typography.makePrimaryLabel()
  private let metadataLabel = Typography.makeSecondaryLabel()
  private let chevron = NSImageView()
  private var clickRecognizer: NSClickGestureRecognizer?

  // MARK: - Initialization

  init(
    family: String,
    sortedModels: [CatalogEntry],
    modelManager: ModelManager,
    isExpanded: Bool,
    onToggle: @escaping (String) -> Void
  ) {
    self.family = family
    self.sortedModels = sortedModels
    self.modelManager = modelManager
    self.isExpanded = isExpanded
    self.onToggle = onToggle
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: - Setup

  /// Configures the view hierarchy and layout constraints.
  private func setup() {
    wantsLayer = true

    // Configure family name label
    familyLabel.stringValue = family
    familyLabel.cell?.lineBreakMode = .byTruncatingTail
    familyLabel.cell?.truncatesLastVisibleLine = true
    familyLabel.maximumNumberOfLines = 1
    familyLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

    // Configure metadata label (showing all available model sizes on same line as family name)
    // Contains all size entries in a single attributed string (e.g., "270M · 1B · 4B · 12B")
    metadataLabel.cell?.lineBreakMode = .byTruncatingTail
    metadataLabel.cell?.truncatesLastVisibleLine = true
    metadataLabel.maximumNumberOfLines = 1
    metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Configure chevron indicator (changes based on expansion state)
    updateChevron()
    chevron.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
    chevron.contentTintColor = Typography.primaryColor

    // Build layout hierarchy: family name and metadata on same line, chevron on right
    let textRow = NSStackView(views: [familyLabel, metadataLabel])
    textRow.orientation = .horizontal
    textRow.spacing = 8
    textRow.alignment = .centerY

    // Main row with flexible space between leading content and chevron
    let hStack = NSStackView(views: [textRow, NSView(), chevron])
    hStack.translatesAutoresizingMaskIntoConstraints = false
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY

    contentView.addSubview(hStack)

    NSLayoutConstraint.activate([
      chevron.widthAnchor.constraint(equalToConstant: 10),
      chevron.heightAnchor.constraint(equalToConstant: 10),
      hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      hStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  // MARK: - View Lifecycle

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard clickRecognizer == nil else { return }

    let click = NSClickGestureRecognizer(target: self, action: #selector(didClickRow(_:)))
    click.buttonMask = 0x1  // Left mouse button only
    addGestureRecognizer(click)
    clickRecognizer = click
  }

  @objc private func didClickRow(_ recognizer: NSClickGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    let location = recognizer.location(in: self)
    guard bounds.contains(location) else { return }

    // Toggle expansion state
    isExpanded.toggle()
    metadataLabel.isHidden = isExpanded
    updateChevron()
    onToggle(family)
  }

  // MARK: - Refresh

  /// Updates the metadata line with current model size states.
  func refresh() {
    metadataLabel.attributedStringValue = makeMetadataLine()
    metadataLabel.isHidden = isExpanded
    updateChevron()
    needsDisplay = true
  }

  private func updateChevron() {
    let symbolName = isExpanded ? "chevron.down" : "chevron.right"
    chevron.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
  }

  // MARK: - Metadata Line Construction

  /// Builds an attributed string showing each unique model build in this family,
  /// highlighting downloads with a checkmark.
  private func makeMetadataLine() -> NSAttributedString {
    // Track seen model IDs to avoid showing duplicate entries in the size list.
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
  /// Unsupported models use a dimmed tertiary label color.
  private func attributedSizeLabel(
    for model: CatalogEntry,
    downloaded: Bool
  ) -> NSAttributedString {
    let isSupported = Catalog.isModelCompatible(model)
    let textColor: NSColor = isSupported ? Typography.secondaryColor : Typography.tertiaryColor

    // Use sizeLabel property which includes quantization suffix (e.g., "27B" or "27B-Q4")
    return NSAttributedString(
      string: model.sizeLabel,
      attributes: [
        .font: Typography.secondary,
        .foregroundColor: textColor,
      ]
    )
  }
}
