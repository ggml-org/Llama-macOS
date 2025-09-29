import AppKit

// Small centered dot separator
final class CenteredDotSeparatorView: NSView {
  private let dotSize: CGFloat = 1.5
  private var sizeConstraints: [NSLayoutConstraint] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.backgroundColor = NSColor.cgColor(.tertiaryLabelColor, in: self)
    layer?.cornerRadius = dotSize / 2
    setHuggingCompression()
    applySizeConstraints()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setHuggingCompression() {
    setContentHuggingPriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .horizontal)
    setContentHuggingPriority(.required, for: .vertical)
    setContentCompressionResistancePriority(.required, for: .vertical)
  }

  private func applySizeConstraints() {
    NSLayoutConstraint.deactivate(sizeConstraints)
    sizeConstraints = [
      widthAnchor.constraint(equalToConstant: dotSize),
      heightAnchor.constraint(equalToConstant: dotSize),
    ]
    NSLayoutConstraint.activate(sizeConstraints)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.backgroundColor = NSColor.cgColor(.tertiaryLabelColor, in: self)
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: dotSize, height: dotSize)
  }
}
