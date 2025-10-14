import AppKit

/// Interactive button to collapse or expand the catalog section.
final class CatalogToggleView: ItemView {
  private let label = Typography.makePrimaryLabel()

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

    contentView.addSubview(label)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
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

  private func updateAccessibilityLabel() {
    setAccessibilityLabel(UserSettings.catalogCollapsed ? "Show catalog" : "Hide catalog")
  }
}
