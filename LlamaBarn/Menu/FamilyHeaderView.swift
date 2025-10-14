import AppKit

/// Interactive header for catalog families that can be collapsed or expanded.
final class FamilyHeaderView: ItemView {
  private let label = Typography.makeTertiaryLabel()
  private let chevronImageView = NSImageView()
  private let family: String
  private let isCollapsed: Bool
  private let onToggle: (String) -> Void

  init(family: String, isCollapsed: Bool, onToggle: @escaping (String) -> Void) {
    self.family = family
    self.isCollapsed = isCollapsed
    self.onToggle = onToggle
    super.init(frame: .zero)
    setup()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 26) }

  private func setup() {
    label.translatesAutoresizingMaskIntoConstraints = false
    label.stringValue = family

    chevronImageView.translatesAutoresizingMaskIntoConstraints = false
    chevronImageView.contentTintColor = .tertiaryLabelColor
    chevronImageView.symbolConfiguration = .init(pointSize: 10, weight: .regular)
    updateChevron()

    contentView.addSubview(label)
    contentView.addSubview(chevronImageView)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

      chevronImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      chevronImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      chevronImageView.widthAnchor.constraint(lessThanOrEqualToConstant: 10),
      chevronImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 10),
    ])

    // Accessibility
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    updateAccessibilityLabel()
  }

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    onToggle(family)
  }

  private func updateChevron() {
    let imageName = isCollapsed ? "chevron.right" : "chevron.down"
    chevronImageView.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
  }

  private func updateAccessibilityLabel() {
    let state = isCollapsed ? "collapsed" : "expanded"
    setAccessibilityLabel("\(family), \(state)")
  }
}
