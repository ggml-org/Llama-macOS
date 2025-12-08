import AppKit

/// Interactive header for catalog families that can be collapsed or expanded.
final class FamilyHeaderView: ItemView {
  private let label = Theme.tertiaryLabel()
  private let sizesLabel = Theme.tertiaryLabel()
  let family: String
  private let sizes: [String]
  private let isCollapsed: Bool
  private let onToggle: (String) -> Void

  init(family: String, sizes: [String], isCollapsed: Bool, onToggle: @escaping (String) -> Void) {
    self.family = family
    self.sizes = sizes
    self.isCollapsed = isCollapsed
    self.onToggle = onToggle
    super.init(frame: .zero)
    setup()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 22) }

  private func setup() {
    label.translatesAutoresizingMaskIntoConstraints = false
    label.stringValue = family

    sizesLabel.translatesAutoresizingMaskIntoConstraints = false
    sizesLabel.stringValue = isCollapsed ? formatSizes() : ""
    sizesLabel.isHidden = !isCollapsed
    sizesLabel.lineBreakMode = .byTruncatingTail
    sizesLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    contentView.addSubview(label)
    contentView.addSubview(sizesLabel)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

      sizesLabel.leadingAnchor.constraint(equalTo: label.trailingAnchor),
      sizesLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      sizesLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
    ])

    // Accessibility
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    updateAccessibilityLabel()
  }

  private func formatSizes() -> String {
    guard !sizes.isEmpty else { return "" }
    return "  ∣  " + sizes.joined(separator: " · ")
  }

  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    // Only toggle if mouse is still within bounds (allows canceling by dragging away)
    if bounds.contains(convert(event.locationInWindow, from: nil)) {
      onToggle(family)
    }
  }

  private func updateAccessibilityLabel() {
    let state = isCollapsed ? "collapsed" : "expanded"
    setAccessibilityLabel("\(family), \(state)")
  }
}
