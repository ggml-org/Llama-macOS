import AppKit

final class SettingsItemView: TitledItemView {
  private let toggle = NSSwitch()
  private let onToggle: (Bool) -> Void
  private let getValue: () -> Bool

  init(
    title: String, getValue: @escaping () -> Bool,
    onToggle: @escaping (Bool) -> Void
  ) {
    self.getValue = getValue
    self.onToggle = onToggle
    super.init(frame: .zero)

    titleLabel.stringValue = title
    // Calculate available width: 300 (menu) - 10 (outer) - 16 (inner) - 40 (toggle) - 8 (spacing) = ~226
    configureSubtitle(nil, width: 220)

    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize {
    // Calculate height based on content
    let width = Layout.menuWidth
    // Force layout to get accurate height
    layoutSubtreeIfNeeded()
    let height = contentView.fittingSize.height + (Layout.verticalPadding * 2)
    return NSSize(width: width, height: max(30, height))
  }

  private func setup() {
    let textStack = makeTextStack()
    textStack.translatesAutoresizingMaskIntoConstraints = false

    toggle.translatesAutoresizingMaskIntoConstraints = false
    toggle.target = self
    toggle.action = #selector(toggleChanged)
    toggle.controlSize = .mini

    contentView.addSubview(textStack)
    contentView.addSubview(toggle)

    NSLayoutConstraint.activate([
      textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),

      // Center text stack vertically, but allow it to push bounds if content is tall
      textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
      textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),

      toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  func refresh() {
    toggle.state = getValue() ? .on : .off
  }

  @objc private func toggleChanged() {
    let isOn = toggle.state == .on
    onToggle(isOn)
  }

  override func mouseUp(with event: NSEvent) {
    toggle.performClick(nil)
  }

  override var highlightEnabled: Bool { false }
}
