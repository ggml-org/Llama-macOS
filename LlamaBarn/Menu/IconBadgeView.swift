import AppKit

/// Small badge that hosts a template image centered inside.
/// Supports both circular and rounded-rectangle corner styles.
/// - Inactive: clear background, primary tint.
/// - Active: filled with `controlAccentColor`, white glyph.
final class IconBadgeView: NSView {
  enum CornerStyle {
    case circular  // corner radius = bounds.height / 2
    case rounded  // corner radius = Layout.cornerRadius
  }

  let imageView = NSImageView()
  private let spinner = NSProgressIndicator()
  private let cornerStyle: CornerStyle

  var isActive: Bool = false { didSet { refresh() } }
  private var isLoading: Bool = false { didSet { refresh() } }

  init(frame frameRect: NSRect = .zero, cornerStyle: CornerStyle = .circular) {
    self.cornerStyle = cornerStyle
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.symbolConfiguration = .init(pointSize: Layout.smallIconSize, weight: .regular)

    // Configure spinner but keep it hidden until used.
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.isDisplayedWhenStopped = false
    spinner.controlSize = .small
    spinner.style = .spinning

    addSubview(imageView)
    addSubview(spinner)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Layout.iconBadgeSize),
      heightAnchor.constraint(equalToConstant: Layout.iconBadgeSize),
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      imageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.smallIconSize),
      imageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.smallIconSize),
      spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layout() {
    super.layout()
    layer?.cornerRadius =
      switch cornerStyle {
      case .circular: bounds.height / 2
      case .rounded: Layout.cornerRadius
      }
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

  /// Show or hide a spinner centered inside the circular badge.
  func setLoading(_ loading: Bool) {
    isLoading = loading
    if loading {
      spinner.startAnimation(nil)
    } else {
      spinner.stopAnimation(nil)
    }
  }

  private func refresh() {
    guard let layer else { return }
    // Spinner appears in the center and the glyph hides while loading.
    imageView.isHidden = isLoading
    spinner.isHidden = !isLoading

    if isActive {
      layer.setBackgroundColor(.controlAccentColor, in: self)
      imageView.contentTintColor = .white
    } else {
      layer.setBackgroundColor(.lbSubtleBackground, in: self)
      // Default (may be overridden by caller for hover emphasis)
      imageView.contentTintColor = Typography.primaryColor
    }
  }
}
