import AppKit

/// Circular container (28pt) for installed model icons that displays state transitions.
/// The icon itself is 16pt, centered within the container.
/// - Inactive: subtle background, tinted icon
/// - Active: blue background, white icon
/// - Loading: shows spinner in place of icon
/// - Downloading: no background; a progress ring around the rim with a pause/play
///   glyph in place of the icon -- see `downloadFraction` / `downloadPaused`
final class IconView: NSView {
  /// Ring stroke. Runs along the chip's own rim, inset by half the stroke.
  private static let ringLineWidth: CGFloat = 2.5

  /// The image view containing the model icon. Set the `image` property directly.
  let imageView = NSImageView()
  private let spinner = NSProgressIndicator()
  /// Pause (in flight) / play (paused) glyph shown in place of the model icon
  /// while the ring is up, making the downloading chip read as a control.
  private let pausePlayView = NSImageView()

  /// Ring layers: a faint full-circle track with a progress arc on top, drawn
  /// with `strokeEnd`. Hidden unless `downloadFraction` is set.
  private let trackLayer = CAShapeLayer()
  private let progressLayer = CAShapeLayer()

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

  /// Swaps the in-ring glyph between pause (in flight) and play (paused).
  /// Only visible while `downloadFraction` is set. Assigned on every progress
  /// tick, so no-op writes bail early instead of rebuilding the symbol image.
  var downloadPaused: Bool = false {
    didSet {
      guard downloadPaused != oldValue else { return }
      let symbol = downloadPaused ? "play.fill" : "pause.fill"
      pausePlayView.image = NSImage(
        systemSymbolName: symbol,
        accessibilityDescription: downloadPaused ? "Resume download" : "Pause download")
      refresh()  // tooltip depends on both this and the downloading state
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

    // Pause/play glyph, sized to sit comfortably inside the ring. Starts as
    // pause (the in-flight symbol); `downloadPaused` swaps it from there.
    pausePlayView.translatesAutoresizingMaskIntoConstraints = false
    pausePlayView.symbolConfiguration = .init(pointSize: 10, weight: .bold)
    pausePlayView.image = NSImage(
      systemSymbolName: "pause.fill", accessibilityDescription: "Pause download")
    pausePlayView.isHidden = true

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
    addSubview(pausePlayView)
    NSLayoutConstraint.activate([
      // Container is fixed at iconViewSize so it can't be squeezed when long titles
      // or hover buttons compete for row width. Intrinsic size alone isn't enough —
      // NSStackView will compress views with default priorities mid-animation.
      widthAnchor.constraint(equalToConstant: Layout.iconViewSize),
      heightAnchor.constraint(equalToConstant: Layout.iconViewSize),
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      imageView.widthAnchor.constraint(equalToConstant: Layout.uiIconSize),
      imageView.heightAnchor.constraint(equalToConstant: Layout.uiIconSize),
      spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
      pausePlayView.centerXAnchor.constraint(equalTo: centerXAnchor),
      pausePlayView.centerYAnchor.constraint(equalTo: centerYAnchor),
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
    // Downloading look: ring in place of the chip background, pause/play glyph
    // in place of the model icon; both restored the moment the download ends.
    let isDownloading = downloadFraction != nil
    trackLayer.isHidden = !isDownloading
    progressLayer.isHidden = !isDownloading
    trackLayer.setStrokeColor(Theme.Colors.subtleBackground, in: self)
    progressLayer.setStrokeColor(Theme.Colors.textSecondary, in: self)
    pausePlayView.isHidden = !isDownloading
    pausePlayView.contentTintColor = .secondaryLabelColor
    toolTip = isDownloading ? (downloadPaused ? "Resume download" : "Pause download") : nil

    // Spinner appears in the center and the glyph hides while loading;
    // the pause/play glyph replaces the icon while downloading.
    imageView.isHidden = isLoading || isDownloading
    spinner.isHidden = !isLoading

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
