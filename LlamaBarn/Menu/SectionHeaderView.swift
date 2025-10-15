import AppKit

final class SectionHeaderView: NSView {
  private let label = Typography.makeTertiaryLabel()
  private let container = NSView()

  init(title: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    setup(title: title)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: Layout.menuWidth, height: 18) }

  private func setup(title: String) {
    // Accessibility
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel(title)

    container.translatesAutoresizingMaskIntoConstraints = false
    label.translatesAutoresizingMaskIntoConstraints = false
    label.stringValue = title

    addSubview(container)
    container.addSubview(label)

    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Layout.outerHorizontalPadding),
      container.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Layout.outerHorizontalPadding),
      container.topAnchor.constraint(equalTo: topAnchor),
      container.bottomAnchor.constraint(equalTo: bottomAnchor),

      label.leadingAnchor.constraint(
        equalTo: container.leadingAnchor, constant: Layout.innerHorizontalPadding),
      label.trailingAnchor.constraint(
        equalTo: container.trailingAnchor, constant: -Layout.innerHorizontalPadding),
      label.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
    ])
  }
}
