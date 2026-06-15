import AppKit

/// Style variants for TextItemView.
enum TextItemStyle {
  case back  // Back navigation with arrow icon
  case title  // Section title (primary font)
  case description  // Multi-line description (tertiary color, wrapping)
}

/// A simple text-based menu item with configurable style and optional action.
/// Handles back buttons, titles, and descriptions in a single unified view.
final class TextItemView: ItemView {
  private let label: NSTextField
  private let iconView: NSImageView?
  private let onAction: (() -> Void)?

  /// Creates a text item view.
  /// - Parameters:
  ///   - text: The text to display
  ///   - style: Visual style (back, title, or description)
  ///   - onAction: Optional action to perform on click. If nil, item is non-interactive.
  init(text: String, style: TextItemStyle = .title, onAction: (() -> Void)? = nil) {
    self.onAction = onAction

    // Configure label and icon based on style
    switch style {
    case .back:
      self.label = Theme.secondaryLabel()
      self.label.textColor = Theme.Colors.textSecondary
      let icon = NSImageView()
      Theme.configure(icon, symbol: "arrow.left", color: Theme.Colors.textSecondary, pointSize: 10)
      self.iconView = icon

    case .title:
      self.label = Theme.primaryLabel()
      self.label.font = Theme.Fonts.primary
      self.label.textColor = Theme.Colors.textPrimary
      self.iconView = nil

    case .description:
      self.label = Theme.tertiaryLabel()
      self.label.cell?.wraps = true
      self.label.cell?.isScrollable = false
      self.label.usesSingleLineMode = false
      self.label.maximumNumberOfLines = 0
      self.label.lineBreakMode = .byWordWrapping
      self.label.preferredMaxLayoutWidth = Layout.contentWidth
      self.iconView = nil
    }

    super.init(frame: .zero)

    label.stringValue = text

    // Build content
    if let iconView {
      let stack = NSStackView(views: [iconView, label])
      stack.orientation = .horizontal
      stack.spacing = 4
      stack.alignment = .centerY
      contentView.addSubview(stack)
      stack.pinToSuperview()
    } else {
      contentView.addSubview(label)
      label.pinToSuperview()
    }
  }

  /// Convenience initializer for back button style.
  convenience init(text: String, showBackArrow: Bool, onAction: (() -> Void)? = nil) {
    self.init(text: text, style: showBackArrow ? .back : .title, onAction: onAction)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var highlightEnabled: Bool { onAction != nil }

  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    if bounds.contains(convert(event.locationInWindow, from: nil)) {
      onAction?()
    }
  }
}
