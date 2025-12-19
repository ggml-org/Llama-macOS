import AppKit

final class SettingsSegmentedView: StandardItemView {
  private let segmentedControl: NSSegmentedControl
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
    self.segmentedControl = NSSegmentedControl(
      labels: labels, trackingMode: .selectOne, target: nil, action: nil)

    super.init(frame: .zero)

    iconView.isHidden = true
    titleLabel.stringValue = title

    setupInfoView()
    configureSegmentedControl()

    accessoryStack.addArrangedSubview(segmentedControl)
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setupInfoView() {
    guard infoText != nil else { return }

    Theme.configure(
      infoIcon, symbol: "info.circle", tooltip: nil,
      color: Theme.Colors.textSecondary)
    infoIcon.addGestureRecognizer(
      NSClickGestureRecognizer(target: self, action: #selector(toggleInfo)))

    // Move subtitleLabel to a new row below the main content
    rootStack.removeFromSuperview()
    let containerStack = NSStackView(views: [rootStack, subtitleLabel])
    containerStack.orientation = .vertical
    containerStack.alignment = .leading
    containerStack.spacing = Layout.textLineSpacing
    contentView.addSubview(containerStack)
    containerStack.pinToSuperview()
    subtitleLabel.isHidden = true
  }

  private func configureSegmentedControl() {
    segmentedControl.target = self
    segmentedControl.action = #selector(segmentChanged)
    segmentedControl.controlSize = .mini
    segmentedControl.font = NSFont.systemFont(ofSize: 10)
    segmentedControl.segmentDistribution = .fillEqually
    segmentedControl.appearance = NSApp.effectiveAppearance
  }

  override func makeTextStack() -> NSStackView {
    if infoText != nil {
      let titleStack = NSStackView(views: [titleLabel, infoIcon])
      titleStack.orientation = .horizontal
      titleStack.spacing = 4
      titleStack.alignment = .centerY
      return titleStack
    }
    return super.makeTextStack()
  }

  override var intrinsicContentSize: NSSize {
    let width = Layout.menuWidth
    layoutSubtreeIfNeeded()
    let height = contentView.fittingSize.height + (Layout.verticalPadding * 2)
    return NSSize(width: width, height: max(30, height))
  }

  func refresh() {
    segmentedControl.selectedSegment = getSelectedIndex()
  }

  @objc private func segmentChanged() {
    onSelect(segmentedControl.selectedSegment)
  }

  @objc private func toggleInfo() {
    guard let infoText = infoText else { return }

    if subtitleLabel.isHidden {
      // Calculate full available width: menu - outer padding - inner padding = 300 - 10 - 16 = 274
      configureSubtitle(infoText, width: 274)
      subtitleLabel.textColor = Theme.Colors.textSecondary
    } else {
      subtitleLabel.isHidden = true
    }

    invalidateIntrinsicContentSize()
    enclosingMenuItem?.menu?.update()
  }

  override var highlightEnabled: Bool { false }
}
