import AppKit

final class SettingsSegmentedView: StandardItemView {
  private let segmentedControl = NSSegmentedControl()
  private let onSelect: (Int) -> Void
  private let getSelectedIndex: () -> Int
  private let infoIcon = NSImageView()
  private let infoText: String?

  init(
    title: String, infoText: String? = nil, labels: [String],
    getSelectedIndex: @escaping () -> Int, onSelect: @escaping (Int) -> Void
  ) {
    self.getSelectedIndex = getSelectedIndex
    self.onSelect = onSelect
    self.infoText = infoText
    super.init(frame: .zero)

    iconView.isHidden = true
    titleLabel.stringValue = title
    // Calculate available width: 300 (menu) - 10 (outer) - 16 (inner) - ~100 (segmented) - 6 (spacing) = ~168
    configureSubtitle(nil, width: 168)

    if infoText != nil {
      Theme.configure(
        infoIcon, symbol: "info.circle", tooltip: nil,
        color: Theme.Colors.textSecondary)
      let recognizer = NSClickGestureRecognizer(target: self, action: #selector(toggleInfo))
      infoIcon.addGestureRecognizer(recognizer)
    }

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

  override func makeTextStack() -> NSStackView {
    if infoText != nil {
      let titleStack = NSStackView(views: [titleLabel, infoIcon])
      titleStack.orientation = .horizontal
      titleStack.spacing = 4
      titleStack.alignment = .centerY

      let stack = NSStackView(views: [titleStack, subtitleLabel])
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = Layout.textLineSpacing
      return stack
    }
    return super.makeTextStack()
  }

  override var intrinsicContentSize: NSSize {
    let width = Layout.menuWidth
    layoutSubtreeIfNeeded()
    let height = contentView.fittingSize.height + (Layout.verticalPadding * 2)
    return NSSize(width: width, height: max(30, height))
  }

  private func setup() {
    accessoryStack.addArrangedSubview(segmentedControl)
    rootStack.alignment = .top
  }

  func refresh() {
    segmentedControl.selectedSegment = getSelectedIndex()
  }

  @objc private func segmentChanged() {
    let selectedIndex = segmentedControl.selectedSegment
    onSelect(selectedIndex)
  }

  @objc private func toggleInfo() {
    guard let infoText = infoText else { return }

    if subtitleLabel.isHidden {
      configureSubtitle(infoText, width: 160)
      subtitleLabel.textColor = Theme.Colors.textSecondary
    } else {
      subtitleLabel.isHidden = true
    }

    invalidateIntrinsicContentSize()
    enclosingMenuItem?.menu?.update()
  }

  override func mouseUp(with event: NSEvent) {
    // Handle click on the view, but since it's segmented, maybe not needed
  }

  override var highlightEnabled: Bool { false }
}
