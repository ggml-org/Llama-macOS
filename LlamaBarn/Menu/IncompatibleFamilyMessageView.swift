import AppKit

final class IncompatibleFamilyMessageView: NSView {
  private let borderLayer = CAShapeLayer()

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true

    let label = Typography.makeTertiaryLabel(
      "None of the models in this family are compatible with your device.")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.maximumNumberOfLines = 2
    label.lineBreakMode = .byWordWrapping
    label.alignment = .left

    addSubview(label)

    let outerV = Layout.verticalPadding
    let innerV = Layout.verticalPadding
    let outerH = Layout.outerHorizontalPadding
    let innerH = Layout.innerHorizontalPadding

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: outerH + innerH),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(outerH + innerH)),
      label.topAnchor.constraint(equalTo: topAnchor, constant: outerV + innerV),
      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(outerV + innerV)),

      // Ensure minimum height
      heightAnchor.constraint(greaterThanOrEqualToConstant: 24),

      // Set width constraint to match menu width
      widthAnchor.constraint(equalToConstant: Layout.menuWidth),
    ])

    setupBorderLayer()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: Layout.menuWidth, height: NSView.noIntrinsicMetric)
  }

  private func setupBorderLayer() {
    borderLayer.lineDashPattern = [3, 3]
    borderLayer.fillColor = nil
    borderLayer.lineWidth = 1
    layer?.addSublayer(borderLayer)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBorderColor()
  }

  override func layout() {
    super.layout()
    let borderRect = bounds.insetBy(dx: Layout.outerHorizontalPadding, dy: Layout.verticalPadding)
    let path = CGPath(
      roundedRect: borderRect,
      cornerWidth: Layout.cornerRadius,
      cornerHeight: Layout.cornerRadius,
      transform: nil
    )
    borderLayer.path = path
    updateBorderColor()
  }

  private func updateBorderColor() {
    var resolved: CGColor = NSColor.clear.cgColor
    effectiveAppearance.performAsCurrentDrawingAppearance {
      resolved = Typography.tertiaryColor.withAlphaComponent(0.5).cgColor
    }
    borderLayer.strokeColor = resolved
  }
}
