import AppKit

final class SettingsItemView: ItemView {
  private let titleLabel: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.font = Theme.Fonts.primary
    label.textColor = Theme.Colors.textPrimary
    return label
  }()
  private let subtitleLabel = Theme.secondaryLabel()
  private let toggle = NSSwitch()
  private let onToggle: (Bool) -> Void
  private let getValue: () -> Bool

  init(
    title: String, subtitle: String? = nil, getValue: @escaping () -> Bool,
    onToggle: @escaping (Bool) -> Void
  ) {
    self.getValue = getValue
    self.onToggle = onToggle
    super.init(frame: .zero)

    titleLabel.stringValue = title
    if let subtitle = subtitle {
      subtitleLabel.stringValue = subtitle
      subtitleLabel.cell?.wraps = true
      subtitleLabel.cell?.isScrollable = false
      subtitleLabel.usesSingleLineMode = false
      subtitleLabel.maximumNumberOfLines = 0
      subtitleLabel.lineBreakMode = .byWordWrapping
      // Calculate available width: 300 (menu) - 10 (outer) - 16 (inner) - 40 (toggle) - 8 (spacing) = ~226
      subtitleLabel.preferredMaxLayoutWidth = 220
    } else {
      subtitleLabel.isHidden = true
    }

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
    let textStack = NSStackView(views: [titleLabel, subtitleLabel])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 2
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

      // Pin text stack to top/bottom to drive content height
      textStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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
}
