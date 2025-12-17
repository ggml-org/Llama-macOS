import AppKit

final class SettingsSegmentedView: TitledItemView {
  private let segmentedControl = NSSegmentedControl()
  private let onSelect: (Int) -> Void
  private let getSelectedIndex: () -> Int

  init(
    title: String, subtitle: String? = nil, labels: [String],
    getSelectedIndex: @escaping () -> Int, onSelect: @escaping (Int) -> Void
  ) {
    self.getSelectedIndex = getSelectedIndex
    self.onSelect = onSelect
    super.init(frame: .zero)

    titleLabel.stringValue = title
    // Calculate available width: 300 (menu) - 10 (outer) - 16 (inner) - ~100 (segmented) - 8 (spacing) = ~166
    configureSubtitle(subtitle, width: 160)

    segmentedControl.segmentCount = labels.count
    for (index, label) in labels.enumerated() {
      segmentedControl.setLabel(label, forSegment: index)
    }
    segmentedControl.target = self
    segmentedControl.action = #selector(segmentChanged)
    segmentedControl.controlSize = .small
    segmentedControl.font = NSFont.systemFont(ofSize: 10)
    segmentedControl.segmentDistribution = .fillEqually
    segmentedControl.appearance = NSApp.effectiveAppearance

    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize {
    let width = Layout.menuWidth
    layoutSubtreeIfNeeded()
    let height = contentView.fittingSize.height + (Layout.verticalPadding * 2)
    return NSSize(width: width, height: max(30, height))
  }

  private func setup() {
    let textStack = makeTextStack()
    textStack.translatesAutoresizingMaskIntoConstraints = false

    segmentedControl.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(textStack)
    contentView.addSubview(segmentedControl)

    NSLayoutConstraint.activate([
      textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      textStack.trailingAnchor.constraint(
        lessThanOrEqualTo: segmentedControl.leadingAnchor, constant: -8),
      textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
      textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),

      segmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      segmentedControl.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
    ])
  }

  func refresh() {
    segmentedControl.selectedSegment = getSelectedIndex()
  }

  @objc private func segmentChanged() {
    let selectedIndex = segmentedControl.selectedSegment
    onSelect(selectedIndex)
  }

  override func mouseUp(with event: NSEvent) {
    // Handle click on the view, but since it's segmented, maybe not needed
  }

  override var highlightEnabled: Bool { false }
}
