import AppKit

/// A standard menu item view with an icon, two lines of text, and an accessory area.
/// Reduces boilerplate for CatalogModelItemView and InstalledModelItemView.
class StandardItemView: ItemView {
  let titleLabel = Theme.primaryLabel()
  let subtitleLabel = Theme.secondaryLabel()
  let iconView = IconView()
  let accessoryStack = NSStackView()
  let rootStack = NSStackView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupStandardLayout()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Creates and configures a vertical stack view containing the title and subtitle labels.
  func makeTextStack() -> NSStackView {
    let stack = NSStackView(views: [titleLabel, subtitleLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = Layout.textLineSpacing
    return stack
  }

  /// Configures the subtitle label for wrapping with a specific maximum width.
  func configureSubtitle(_ text: String?, width: CGFloat) {
    if let text = text {
      subtitleLabel.stringValue = text
      subtitleLabel.cell?.wraps = true
      subtitleLabel.cell?.isScrollable = false
      subtitleLabel.usesSingleLineMode = false
      subtitleLabel.maximumNumberOfLines = 0
      subtitleLabel.lineBreakMode = .byWordWrapping
      subtitleLabel.preferredMaxLayoutWidth = width
      subtitleLabel.isHidden = false
    } else {
      subtitleLabel.isHidden = true
    }
  }

  private func setupStandardLayout() {
    // Text column
    let textColumn = makeTextStack()

    // Leading: Icon + Text
    let leading = NSStackView(views: [iconView, textColumn])
    leading.orientation = .horizontal
    leading.alignment = .centerY
    leading.spacing = 6

    // Spacer to push accessory stack to the right
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Accessory Stack (initially empty)
    accessoryStack.orientation = .horizontal
    accessoryStack.alignment = .centerY
    accessoryStack.spacing = 6

    // Root Stack
    rootStack.setViews([leading, spacer, accessoryStack], in: .leading)
    rootStack.orientation = .horizontal
    rootStack.alignment = .centerY  // Align everything to center vertically
    rootStack.spacing = 6

    contentView.addSubview(rootStack)
    rootStack.pinToSuperview()
  }
}
