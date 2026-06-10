import AppKit

/// Trailing row under the Recommended suggestions that links to the web catalog
/// for more models — the curated picks are a starting point, and the catalog has
/// more (it's curated, not all of Hugging Face, hence "more" not "all"). Styled
/// like the empty-state browse link.
final class BrowseMoreRow: ItemView {
  private let url: URL

  // Plain link text, like the empty-state browse link — no row highlight, which
  // on a single short line would read as a chunky gray box.
  override var highlightEnabled: Bool { false }

  init(url: URL) {
    self.url = url
    super.init(frame: .zero)

    let link = Theme.secondaryLabel()
    link.attributedStringValue = NSAttributedString(
      string: "Browse more →",
      attributes: [.foregroundColor: NSColor.linkColor, .font: Theme.Fonts.secondary])
    link.isSelectable = false

    let stack = NSStackView(views: [link])
    stack.orientation = .horizontal
    stack.alignment = .centerY
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
