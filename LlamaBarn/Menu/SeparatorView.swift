import AppKit

/// Custom separator view with controllable width and color.
final class SeparatorView: NSView {
  private let line = NSView()

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    // Match standard menu item height or slightly less for separator
    heightAnchor.constraint(equalToConstant: 12).isActive = true
    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true

    line.translatesAutoresizingMaskIntoConstraints = false
    line.wantsLayer = true

    addSubview(line)

    // Align with content (outer + inner padding)
    // This makes the separator start where the text starts, which is "wider" than standard system separator
    // and "closer to the edges" (13px vs ~16px).
    let padding = Layout.outerHorizontalPadding + Layout.innerHorizontalPadding

    NSLayoutConstraint.activate([
      line.heightAnchor.constraint(equalToConstant: 1),
      line.centerYAnchor.constraint(equalTo: centerYAnchor),
      line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
      line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func updateLayer() {
    line.layer?.backgroundColor = Theme.Colors.separator.cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateLayer()
  }
}
