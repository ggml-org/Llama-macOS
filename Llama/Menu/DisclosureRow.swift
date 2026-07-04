import AppKit

/// A flush-left disclosure row that toggles a collapsed list open or closed --
/// e.g. "Show 14 more" under a truncated Installed list, and "Show less" once
/// expanded. Modeled on `BrowseModelsRow`: hover highlight, tertiary text, a
/// leading chevron that points down when collapsed (reveals more below) and up
/// when expanded.
final class DisclosureRow: ItemView {
  private let onClick: () -> Void

  init(title: String, expanded: Bool, onClick: @escaping () -> Void) {
    self.onClick = onClick
    super.init(frame: .zero)

    let chevron = NSImageView()
    let symbol = expanded ? "chevron.up" : "chevron.down"
    Theme.configure(chevron, symbol: symbol, color: .tertiaryLabelColor)
    Layout.constrainToIconSize(chevron)

    let label = Theme.tertiaryLabel(title)

    // Flush left like BrowseModelsRow / the section header -- the row is about the
    // whole list, so it shouldn't indent as if it belonged to the model above.
    let stack = NSStackView(views: [chevron, label])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 4
    contentView.addSubview(stack)
    stack.pinToSuperview()

    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true

    addGesture(action: #selector(didClick))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func didClick() {
    onClick()
  }
}
