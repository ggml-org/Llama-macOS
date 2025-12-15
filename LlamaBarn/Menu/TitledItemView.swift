import AppKit

/// Base class for menu items that display a title and an optional subtitle.
class TitledItemView: ItemView {
  let titleLabel = Theme.primaryLabel()
  let subtitleLabel = Theme.secondaryLabel()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
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
}
