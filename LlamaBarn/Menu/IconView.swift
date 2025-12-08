import AppKit

/// Circular container (28pt) for installed model icons that displays state transitions.
/// The icon itself remains 16pt, centered within the container.
/// - Inactive: subtle background, tinted icon
/// - Active: blue background, white icon
/// - Loading: shows spinner in place of icon
final class IconView: NSView {
  /// The image view containing the model icon. Set the `image` property directly.
  let imageView = NSImageView()
  private let spinner = NSProgressIndicator()

  var isActive: Bool = false { didSet { refresh() } }
  private var isLoading: Bool = false { didSet { refresh() } }
  var inactiveTintColor: NSColor = Typography.primaryColor { didSet { refresh() } }

  var inactiveBackgroundColor: NSColor = .lbSubtleBackground { didSet { refresh() } }

  override init(frame frameRect: NSRect = .zero) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.symbolConfiguration = .init(pointSize: Layout.uiIconSize, weight: .regular)

    // Configure spinner but keep it hidden until used.
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.isDisplayedWhenStopped = false
    spinner.controlSize = .small
    spinner.style = .spinning

    addSubview(imageView)
    addSubview(spinner)
    NSLayoutConstraint.activate([
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      imageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
      imageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
      spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    refresh()
  }

  override func layout() {
    super.layout()
    // Make circular by setting corner radius to half the view's size
    layer?.cornerRadius = bounds.width / 2
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
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
      layer.setBackgroundColor(inactiveBackgroundColor, in: self)
      imageView.contentTintColor = inactiveTintColor
    }
  }
}
