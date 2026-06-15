import AppKit

/// Trailing row under the Recommended suggestions that links to the web catalog
/// for more models — the curated picks are a starting point, and the catalog has
/// more (it's curated, not all of Hugging Face, hence "more" not "all").
/// Behaves like a regular menu item: hover highlight, standard text colors —
/// the trailing arrow signals it navigates away.
final class BrowseMoreRow: ItemView {
  private let url: URL

  init(url: URL) {
    self.url = url
    super.init(frame: .zero)

    // Gray secondary text, not primary -- section headers are 11pt primary
    // flush left, so matching them exactly made this read as another header.
    let link = Theme.tertiaryLabel("Browse more →")

    // Flush left like the section header -- the row is about the whole list,
    // and indenting it would read as belonging to the last model above.
    let stack = NSStackView(views: [link])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 0
    contentView.addSubview(stack)
    stack.pinToSuperview()

    // No fixed height — the row sizes to the link plus ItemView's standard
    // vertical padding, matching the menu's text-row rhythm.
    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true

    addGesture(action: #selector(openBrowse))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func openBrowse() {
    NSWorkspace.shared.open(url)
  }
}
