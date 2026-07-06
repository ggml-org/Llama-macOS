import AppKit

/// Circular container (28pt) for installed model icons that displays state transitions.
/// The icon itself is 16pt, centered within the container (13pt while downloading).
/// - Inactive: subtle background, tinted icon
/// - Active: blue background, white icon
/// - Loading: shows spinner in place of icon
/// - Downloading: no background; a progress ring around the rim with the icon
///   shrunk inside it (the Chrome favicon-loading pattern) -- see `downloadFraction`
final class IconView: NSView {
  /// Ring stroke. Runs along the chip's own rim, inset by half the stroke.
  private static let ringLineWidth: CGFloat = 3
  /// Icon size while the ring is shown. Slightly smaller than the resting 16pt
  /// so the glyph clears the ring, mirroring how Chrome shrinks the favicon
  /// while a page loads and restores it when done.
  private static let downloadingIconSize: CGFloat = 13

  /// The image view containing the model icon. Set the `image` property directly.
  let imageView = NSImageView()
  private let spinner = NSProgressIndicator()

  /// Ring layers: a faint full-circle track with a progress arc on top, drawn
  /// with `strokeEnd`. Hidden unless `downloadFraction` is set.
  private let trackLayer = CAShapeLayer()
  private let progressLayer = CAShapeLayer()

  /// Icon size constraints, kept so the glyph can shrink while downloading.
  private var iconWidthConstraint: NSLayoutConstraint!
  private var iconHeightConstraint: NSLayoutConstraint!

  var isActive: Bool = false { didSet { refresh() } }
  private var isLoading: Bool = false { didSet { refresh() } }
  var inactiveTintColor: NSColor = Theme.Colors.textPrimary { didSet { refresh() } }

  var inactiveBackgroundColor: NSColor = Theme.Colors.subtleBackground { didSet { refresh() } }

  /// Download progress in 0...1, or nil when not downloading. Non-nil swaps the
  /// chip into its downloading look: background dropped, icon shrunk, ring shown.
  /// The arc floors at a small visible sliver so a just-started download reads
  /// as "a ring beginning to fill" rather than an empty circle.
  var downloadFraction: Double? {
    didSet {
      updateRingProgress()
      // Only rebuild the whole look on show/hide, not on every progress tick.
      if (downloadFraction == nil) != (oldValue == nil) { refresh() }
    }
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: Layout.iconViewSize, height: Layout.iconViewSize)
  }

  override init(frame frameRect: NSRect = .zero) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.symbolConfiguration = .init(pointSize: Layout.uiIconSize, weight: .regular)
    // Scale into whatever frame the size constraints dictate, so both brand
    // logos and SF Symbols shrink cleanly in the downloading state.
    imageView.imageScaling = .scaleProportionallyUpOrDown

    for shape in [trackLayer, progressLayer] {
      shape.fillColor = nil
      shape.lineWidth = Self.ringLineWidth
      shape.lineCap = .round
      shape.isHidden = true
      layer?.addSublayer(shape)
    }

    // Configure spinner but keep it hidden until used.
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.isDisplayedWhenStopped = false
    spinner.controlSize = .small
    spinner.style = .spinning

    addSubview(imageView)
    addSubview(spinner)
    iconWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: Layout.uiIconSize)
    iconHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: Layout.uiIconSize)
    NSLayoutConstraint.activate([
      // Container is fixed at iconViewSize so it can't be squeezed when long titles
      // or hover buttons compete for row width. Intrinsic size alone isn't enough —
      // NSStackView will compress views with default priorities mid-animation.
      widthAnchor.constraint(equalToConstant: Layout.iconViewSize),
      heightAnchor.constraint(equalToConstant: Layout.iconViewSize),
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconWidthConstraint,
      iconHeightConstraint,
      spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    refresh()
  }

  override func layout() {
    super.layout()
    // Make circular by setting corner radius to half the view's size
    layer?.cornerRadius = bounds.width / 2

    // Ring path along the rim, inset by half the stroke so it isn't clipped.
    // Start at 12 o'clock and run visually clockwise: in the layer's default
    // (y-up) coordinates that's from π/2 sweeping through decreasing angles.
    let radius = bounds.width / 2 - Self.ringLineWidth / 2
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let path = CGMutablePath()
    path.addArc(
      center: center, radius: radius,
      startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
    trackLayer.frame = bounds
    progressLayer.frame = bounds
    trackLayer.path = path
    progressLayer.path = path
    updateRingProgress()
  }

  private func updateRingProgress() {
    guard let fraction = downloadFraction else { return }
    // Snap to each progress sample instead of trailing behind with an implicit fade.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    progressLayer.strokeEnd = CGFloat(max(0.04, min(1, fraction)))
    CATransaction.commit()
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

    // Downloading look: ring in place of the chip background, icon shrunk so it
    // clears the ring; restored to full size the moment the download ends.
    let isDownloading = downloadFraction != nil
    trackLayer.isHidden = !isDownloading
    progressLayer.isHidden = !isDownloading
    trackLayer.setStrokeColor(Theme.Colors.subtleBackground, in: self)
    progressLayer.setStrokeColor(Theme.Colors.textSecondary, in: self)
    let iconSize = isDownloading ? Self.downloadingIconSize : Layout.uiIconSize
    iconWidthConstraint.constant = iconSize
    iconHeightConstraint.constant = iconSize
    // Re-render symbols at the target size rather than downscaling the 16pt
    // raster into the 12pt frame -- scaled bitmaps of SF Symbols look blurry.
    imageView.symbolConfiguration = .init(pointSize: iconSize, weight: .regular)

    if isActive {
      layer.setBackgroundColor(.controlAccentColor, in: self)
      imageView.contentTintColor = .white
      // Spinner always white on blue background regardless of theme
      spinner.appearance = NSAppearance(named: .darkAqua)
    } else {
      layer.setBackgroundColor(isDownloading ? .clear : inactiveBackgroundColor, in: self)
      imageView.contentTintColor = inactiveTintColor
    }
  }
}
