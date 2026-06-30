import AppKit

/// Placeholder shown under the Installed header when no models are installed yet.
///
/// Replaces a flush-left line of tertiary text that read as a header subtitle.
/// Instead it occupies the same footprint as a model row — same width and 40pt
/// height — with centered text and a subtle dashed outline, so it reads as an
/// empty slot waiting to be filled. Matching the row height also means the menu
/// doesn't resize the moment the first download replaces this with a real row.
final class EmptyInstalledRow: ItemView {
  // Dashed rounded outline tracing the content area, to signal "an empty slot
  // goes here." Drawn on contentView (not backgroundView) so it stops at the
  // content edge — a permanent element shouldn't bleed into the menu's side
  // margins; only the transient hover highlight is allowed to.
  private let outline = CAShapeLayer()

  init() {
    super.init(frame: .zero)

    let label = Theme.tertiaryLabel("No models yet")
    label.alignment = .center
    contentView.addSubview(label)
    // Center in the row rather than pinning to the leading edge — centered text
    // reads as a placeholder, not a header label.
    label.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])

    // Same footprint as a model row (ModelItemView / CatalogItemView).
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Layout.menuWidth),
      heightAnchor.constraint(equalToConstant: 40),
    ])

    outline.fillColor = nil
    outline.lineWidth = 1
    outline.lineDashPattern = [4, 3]
    contentView.wantsLayer = true
    contentView.layer?.addSublayer(outline)
    refreshOutlineColor()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // Static placeholder — no hover affordance.
  override var highlightEnabled: Bool { false }

  override func layout() {
    super.layout()
    // Trace the content area, inset half a line so the stroke isn't clipped by
    // the layer bounds.
    let rect = contentView.bounds.insetBy(dx: 0.5, dy: 0.5)
    outline.frame = contentView.bounds
    outline.path = CGPath(
      roundedRect: rect, cornerWidth: Layout.cornerRadius, cornerHeight: Layout.cornerRadius,
      transform: nil)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshOutlineColor()
  }

  private func refreshOutlineColor() {
    // CAShapeLayer takes a CGColor, so resolve the dynamic border color for the
    // current appearance.
    effectiveAppearance.performAsCurrentDrawingAppearance {
      outline.strokeColor = Theme.Colors.border.cgColor
    }
  }
}
