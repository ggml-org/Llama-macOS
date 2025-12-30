import AppKit

/// Interactive header for catalog families.
final class FamilyHeaderView: ItemView {
  private let label = Theme.tertiaryLabel()
  private let leadingChevron = NSImageView()
  private let trailingChevron = NSImageView()
  let family: String
  private let onAction: ((String) -> Void)?

  init(
    family: String,
    sizes: [String],
    showChevron: Bool = true,
    showBackChevron: Bool = false,
    onAction: ((String) -> Void)? = nil
  ) {
    self.family = family
    self.onAction = onAction
    super.init(frame: .zero)

    label.translatesAutoresizingMaskIntoConstraints = false
    label.attributedStringValue = Format.familyHeader(name: family, sizes: sizes)
    label.lineBreakMode = .byTruncatingTail

    leadingChevron.translatesAutoresizingMaskIntoConstraints = false
    Theme.configure(
      leadingChevron, symbol: "chevron.left", color: Theme.Colors.textSecondary, pointSize: 11)
    leadingChevron.isHidden = !showBackChevron

    trailingChevron.translatesAutoresizingMaskIntoConstraints = false
    Theme.configure(
      trailingChevron, symbol: "chevron.right", color: Theme.Colors.textSecondary, pointSize: 11)
    trailingChevron.isHidden = onAction == nil || !showChevron

    contentView.addSubview(label)
    contentView.addSubview(leadingChevron)
    contentView.addSubview(trailingChevron)

    NSLayoutConstraint.activate([
      leadingChevron.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      leadingChevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      leadingChevron.widthAnchor.constraint(equalToConstant: 12),
      leadingChevron.heightAnchor.constraint(equalToConstant: 12),

      label.leadingAnchor.constraint(
        equalTo: showBackChevron ? leadingChevron.trailingAnchor : contentView.leadingAnchor,
        constant: showBackChevron ? 4 : 0
      ),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      label.trailingAnchor.constraint(
        lessThanOrEqualTo: trailingChevron.leadingAnchor, constant: -4),

      trailingChevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      trailingChevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      trailingChevron.widthAnchor.constraint(equalToConstant: 12),
      trailingChevron.heightAnchor.constraint(equalToConstant: 12),
    ])

    // Accessibility
    if onAction != nil {
      setAccessibilityElement(true)
      setAccessibilityRole(.button)
      setAccessibilityLabel(family)
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var highlightEnabled: Bool { onAction != nil }

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 22) }

  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    // Only toggle if mouse is still within bounds (allows canceling by dragging away)
    if bounds.contains(convert(event.locationInWindow, from: nil)), let onAction = onAction {
      onAction(family)
    }
  }
}
