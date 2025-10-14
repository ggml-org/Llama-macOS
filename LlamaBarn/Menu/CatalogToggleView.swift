import AppKit

/// Interactive button to collapse or expand the catalog section.
final class CatalogToggleView: ItemView {
  private let label = Typography.makePrimaryLabel()
  private let chevronImageView = NSImageView()

  init() {
    super.init(frame: .zero)
    setup()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 24) }

  private func setup() {
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textColor = .secondaryLabelColor
    updateLabel()

    chevronImageView.translatesAutoresizingMaskIntoConstraints = false
    chevronImageView.contentTintColor = .secondaryLabelColor
    chevronImageView.symbolConfiguration = .init(pointSize: Layout.uiIconSize, weight: .regular)
    updateChevron()

    contentView.addSubview(label)
    contentView.addSubview(chevronImageView)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

      chevronImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      chevronImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      chevronImageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
      chevronImageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
    ])

    // Accessibility
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    updateAccessibilityLabel()
  }

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    UserSettings.catalogCollapsed.toggle()
    // No need to update label - the menu will rebuild when settings change
  }

  private func updateLabel() {
    label.stringValue = UserSettings.catalogCollapsed ? "Show catalog" : "Hide catalog"
  }

  private func updateChevron() {
    let imageName = UserSettings.catalogCollapsed ? "chevron.down" : "chevron.up"
    chevronImageView.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
  }

  private func updateAccessibilityLabel() {
    setAccessibilityLabel(UserSettings.catalogCollapsed ? "Show catalog" : "Hide catalog")
  }
}
