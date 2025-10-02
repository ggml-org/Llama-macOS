import AppKit

final class SectionHeaderMenuItemView: NSView {
  private let label = NSTextField(labelWithString: "")
  private let container = NSView()

  init(title: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    setup(title: title)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 18) }

  private func setup(title: String) {
    // Accessibility
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel(title)

    container.translatesAutoresizingMaskIntoConstraints = false
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = Typography.secondary
    label.textColor = .secondaryLabelColor
    label.stringValue = title
    label.lineBreakMode = .byTruncatingTail

    addSubview(container)
    container.addSubview(label)

    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Metrics.outerHorizontalPadding),
      container.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Metrics.outerHorizontalPadding),
      container.topAnchor.constraint(equalTo: topAnchor),
      container.bottomAnchor.constraint(equalTo: bottomAnchor),

      label.leadingAnchor.constraint(
        equalTo: container.leadingAnchor, constant: Metrics.innerHorizontalPadding),
      label.trailingAnchor.constraint(
        equalTo: container.trailingAnchor, constant: -Metrics.innerHorizontalPadding),
      label.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
    ])
  }
}
