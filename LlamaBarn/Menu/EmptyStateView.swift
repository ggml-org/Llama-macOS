import AppKit

/// Shown in place of the installed section when no models are present.
/// Guides the user to install their first model from Hugging Face.
final class EmptyStateView: ItemView {
  /// Web catalog where users can browse and install models.
  private static let browseUrl = URL(string: "https://llama.app/")!

  override var highlightEnabled: Bool { false }

  init() {
    super.init(frame: .zero)
    setup()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setup() {
    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true

    let title = Theme.primaryLabel("No models yet")

    let description = Theme.tertiaryLabel(
      "Browse GGUF models on Hugging Face and open them in Llama.")
    description.cell?.wraps = true
    description.cell?.isScrollable = false
    description.usesSingleLineMode = false
    description.maximumNumberOfLines = 0
    description.lineBreakMode = .byWordWrapping
    description.preferredMaxLayoutWidth = Layout.contentWidth

    let link = Theme.secondaryLabel()
    link.attributedStringValue = NSAttributedString(
      string: "→ Browse models",
      attributes: [.foregroundColor: NSColor.linkColor, .font: Theme.Fonts.secondary])
    link.isSelectable = false
    addGesture(to: link, action: #selector(openBrowse))

    let stack = NSStackView(views: [title, description, link])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = Layout.textLineSpacing
    stack.setCustomSpacing(8, after: description)

    contentView.addSubview(stack)
    stack.pinToSuperview()
  }

  @objc private func openBrowse() {
    NSWorkspace.shared.open(Self.browseUrl)
  }
}
