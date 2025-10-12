import AppKit

/// Icon that changes color based on state.
/// - Inactive: uses inactiveTintColor
/// - Active: uses controlAccentColor
final class IconView: NSView {
  let imageView = NSImageView()
  private let spinner = NSProgressIndicator()

  var isActive: Bool = false { didSet { refresh() } }
  private var isLoading: Bool = false { didSet { refresh() } }
  var inactiveTintColor: NSColor = Typography.primaryColor { didSet { refresh() } }

  override init(frame frameRect: NSRect = .zero) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.symbolConfiguration = .init(pointSize: Layout.iconSize, weight: .regular)

    // Configure spinner but keep it hidden until used.
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.isDisplayedWhenStopped = false
    spinner.controlSize = .small
    spinner.style = .spinning

    addSubview(imageView)
    addSubview(spinner)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Layout.iconSize),
      heightAnchor.constraint(equalToConstant: Layout.iconSize),
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      imageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.iconSize),
      imageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.iconSize),
      spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
  }

  func setImage(_ image: NSImage?) {
    imageView.image = image
    refresh()
  }

  /// Show or hide a spinner centered in place of the icon.
  func setLoading(_ loading: Bool) {
    isLoading = loading
    if loading {
      spinner.startAnimation(nil)
    } else {
      spinner.stopAnimation(nil)
    }
  }

  private func refresh() {
    // Spinner appears in the center and the glyph hides while loading.
    imageView.isHidden = isLoading
    spinner.isHidden = !isLoading

    if isActive {
      imageView.contentTintColor = .controlAccentColor
    } else {
      imageView.contentTintColor = inactiveTintColor
    }
  }
}
