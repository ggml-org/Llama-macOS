import AppKit

/// Interactive header for catalog families that can be collapsed or expanded.
final class FamilyHeaderView: ItemView {
  private let label = Theme.tertiaryLabel()
  let family: String
  private let onToggle: (String) -> Void

  init(family: String, sizes: [String], isCollapsed: Bool, onToggle: @escaping (String) -> Void) {
    self.family = family
    self.onToggle = onToggle
    super.init(frame: .zero)

    let sizesText = sizes.isEmpty ? "" : "  ∣  " + sizes.joined(separator: " · ")

    label.translatesAutoresizingMaskIntoConstraints = false
    label.stringValue = family + sizesText
    label.lineBreakMode = .byTruncatingTail

    contentView.addSubview(label)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
    ])

    // Accessibility
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    let state = isCollapsed ? "collapsed" : "expanded"
    setAccessibilityLabel("\(family), \(state)")
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 22) }

  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    // Only toggle if mouse is still within bounds (allows canceling by dragging away)
    if bounds.contains(convert(event.locationInWindow, from: nil)) {
      onToggle(family)
    }
  }
}
