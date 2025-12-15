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
    configureSubtitle(subtitle, width: 270)

    segmentedControl.segmentCount = labels.count
    for (index, label) in labels.enumerated() {
      segmentedControl.setLabel(label, forSegment: index)
    }
    segmentedControl.target = self
    segmentedControl.action = #selector(segmentChanged)
    segmentedControl.controlSize = .mini
    segmentedControl.font = NSFont.systemFont(ofSize: 10)

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

    let mainStack = NSStackView(views: [textStack, segmentedControl])
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.spacing = 8
    mainStack.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(mainStack)

    NSLayoutConstraint.activate([
      mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      // Make segmented control full width
      segmentedControl.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
      segmentedControl.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
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
