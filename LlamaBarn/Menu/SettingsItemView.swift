import AppKit

final class SettingsItemView: StandardItemView {
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

    iconView.isHidden = true
    titleLabel.stringValue = title
    // Calculate available width: 300 (menu) - 10 (outer) - 16 (inner) - 40 (toggle) - 6 (spacing) = ~228
    configureSubtitle(nil, width: 228)

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
    toggle.target = self
    toggle.action = #selector(toggleChanged)
    toggle.controlSize = .mini

    accessoryStack.addArrangedSubview(toggle)
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
