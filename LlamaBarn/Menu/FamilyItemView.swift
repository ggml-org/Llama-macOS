import AppKit

/// Interactive item for catalog families.
final class FamilyItemView: StandardItemView {
  let family: String
  private let onAction: ((String) -> Void)?
  private let chevronView = NSImageView()

  init(
    family: String,
    sizes: [(String, Bool)],
    description: String? = nil,
    onAction: ((String) -> Void)? = nil
  ) {
    self.family = family
    self.onAction = onAction
    super.init(frame: .zero)

    // Configure StandardItemView elements
    iconView.isHidden = true

    // Title
    titleLabel.font = Theme.Fonts.secondary
    titleLabel.textColor = Theme.Colors.textSecondary
    titleLabel.attributedStringValue = Format.familyItem(name: family, sizes: sizes)
    titleLabel.lineBreakMode = .byTruncatingTail

    // Subtitle (Description)
    subtitleLabel.textColor = Theme.Colors.textSecondary

    // Calculate available width:
    // Menu (300) - Outer (5*2) - Inner (8*2) - Chevron (10) - Spacing (6) = ~258
    let availableWidth =
      Layout.menuWidth - (Layout.outerHorizontalPadding * 2) - (Layout.innerHorizontalPadding * 2)
      - 16
    configureSubtitle(description, width: availableWidth)

    if description != nil {
      subtitleLabel.maximumNumberOfLines = 1
      subtitleLabel.lineBreakMode = .byTruncatingTail
      subtitleLabel.cell?.truncatesLastVisibleLine = true
      subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    // Chevron
    Theme.configure(
      chevronView,
      symbol: "chevron.right",
      color: .tertiaryLabelColor,
      pointSize: 10
    )
    chevronView.isHidden = onAction == nil

    accessoryStack.addArrangedSubview(chevronView)

    // Accessibility
    if onAction != nil {
      setAccessibilityElement(true)
      setAccessibilityRole(.button)
      setAccessibilityLabel(family)
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var highlightEnabled: Bool { onAction != nil }

  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    // Only toggle if mouse is still within bounds (allows canceling by dragging away)
    if bounds.contains(convert(event.locationInWindow, from: nil)), let onAction = onAction {
      onAction(family)
    }
  }
}
