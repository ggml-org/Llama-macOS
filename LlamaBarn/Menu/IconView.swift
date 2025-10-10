import AppKit

/// Small badge that hosts a template image centered inside.
/// Uses rounded corners matching Layout.cornerRadius.
/// - Inactive: clear background, primary tint.
/// - Active: filled with `controlAccentColor`, white glyph.
final class IconView: NSView {
  let imageView = NSImageView()
  private let spinner = NSProgressIndicator()

  var isActive: Bool = false { didSet { refresh() } }
  private var isLoading: Bool = false { didSet { refresh() } }
  var inactiveTintColor: NSColor = Typography.primaryColor { didSet { refresh() } }

  override init(frame frameRect: NSRect = .zero) {
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
    layer?.cornerRadius = Layout.cornerRadius
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
  }

  func setImage(_ image: NSImage?) {
    imageView.image = image
    refresh()
  }

  /// Show or hide a spinner centered inside the badge.
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
      // Spinner always white on blue background regardless of theme
      spinner.appearance = NSAppearance(named: .darkAqua)
    } else {
      layer.setBackgroundColor(.lbSubtleBackground, in: self)
      imageView.contentTintColor = inactiveTintColor
    }
  }
}
