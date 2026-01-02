import AppKit

/// A clickable menu item for navigating back to the catalog.
final class BackItemView: ItemView {
  private let onAction: () -> Void
  private let iconView = NSImageView()
  private let label = Theme.secondaryLabel()

  init(title: String, onAction: @escaping () -> Void) {
    self.onAction = onAction
    super.init(frame: .zero)

    // Icon
    Theme.configure(
      iconView,
      symbol: "chevron.left",
      color: Theme.Colors.textSecondary,
      pointSize: 10
    )

    // Label
    label.stringValue = title
    label.textColor = Theme.Colors.textSecondary

    // Stack
    let stack = NSStackView(views: [iconView, label])
    stack.orientation = .horizontal
    stack.spacing = 4
    stack.alignment = .centerY

    contentView.addSubview(stack)
    stack.pinToSuperview()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var highlightEnabled: Bool { true }

  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    if bounds.contains(convert(event.locationInWindow, from: nil)) {
      onAction()
    }
  }
}

/// A non-interactive header item for the family detail view.
final class TitleItemView: ItemView {
  private let label = Theme.primaryLabel()

  init(text: String) {
    super.init(frame: .zero)

    label.stringValue = text
    label.font = Theme.Fonts.primary
    label.textColor = Theme.Colors.textPrimary

    contentView.addSubview(label)
    label.pinToSuperview()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var highlightEnabled: Bool { false }
}
