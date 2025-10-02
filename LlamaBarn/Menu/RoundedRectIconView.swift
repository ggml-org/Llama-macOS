import AppKit

/// Small rounded-rectangle badge that hosts a template image centered inside.
/// Mirrors `CircularIconView` styling but uses a fixed corner radius
/// so it can visually distinguish non-interactive family items from
/// the circular installed-model icons which have an active state.
final class RoundedRectIconView: NSView {
  let imageView = NSImageView()

  // Kept for API parity with CircularIconView; family items never set active.
  var isActive: Bool = false { didSet { refresh() } }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.symbolConfiguration = .init(pointSize: Metrics.smallIconSize, weight: .regular)
    imageView.imageScaling = .scaleProportionallyDown

    addSubview(imageView)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      heightAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      imageView.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.smallIconSize),
      imageView.heightAnchor.constraint(lessThanOrEqualToConstant: Metrics.smallIconSize),
    ])
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layout() {
    super.layout()
    layer?.cornerRadius = Metrics.cornerRadius
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
  }

  func setImage(_ image: NSImage?) {
    imageView.image = image
    if let img = imageView.image { img.isTemplate = true }
    refresh()
  }

  private func refresh() {
    guard let layer else { return }
    if isActive {
      // Keep parity with circular style if ever reused interactively.
      layer.borderWidth = 0
      layer.setBackgroundColor(.controlAccentColor, in: self)
      imageView.contentTintColor = .white
    } else {
      layer.borderWidth = 0
      layer.setBackgroundColor(.lbBadgeBackground, in: self)
      imageView.contentTintColor = .labelColor
    }
  }
}
