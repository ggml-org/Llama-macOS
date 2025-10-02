import AppKit

/// Minimal base class for custom NSMenu item rows.
/// Provides a shared background container with hover highlight and a content area for subclasses.
class MenuRowView: NSView {
  let backgroundView = NSView()
  let contentView = NSView()

  private var trackingArea: NSTrackingArea?
  private(set) var isHoverHighlighted = false

  // MARK: - Customization hooks

  /// Override to disable hover highlight based on dynamic state (e.g., only when server is running).
  var hoverHighlightEnabled: Bool { true }
  /// Override to change corner radius of the background.
  var hoverCornerRadius: CGFloat { Metrics.cornerRadius }
  /// Called whenever the hover highlight changes.
  func hoverHighlightDidChange(_ highlighted: Bool) {}

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    setupContainers()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setupContainers() {
    wantsLayer = true
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.wantsLayer = true
    contentView.translatesAutoresizingMaskIntoConstraints = false

    addSubview(backgroundView)
    backgroundView.addSubview(contentView)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Metrics.outerHorizontalPadding),
      backgroundView.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Metrics.outerHorizontalPadding),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

      contentView.leadingAnchor.constraint(
        equalTo: backgroundView.leadingAnchor, constant: Metrics.innerHorizontalPadding),
      contentView.trailingAnchor.constraint(
        equalTo: backgroundView.trailingAnchor, constant: -Metrics.innerHorizontalPadding),
      contentView.topAnchor.constraint(
        equalTo: backgroundView.topAnchor, constant: Metrics.verticalPadding),
      contentView.bottomAnchor.constraint(
        equalTo: backgroundView.bottomAnchor, constant: -Metrics.verticalPadding),
    ])
  }

  // MARK: - Hover handling

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
    addTrackingArea(trackingArea!)
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    guard !usesMenuManagedHighlight else { return }
    guard hoverHighlightEnabled else { return }
    setHoverHighlight(true)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    guard !usesMenuManagedHighlight else { return }
    setHoverHighlight(false)
  }

  /// Programmatically set hover highlight (e.g., to clear highlight when state changes).
  func setHoverHighlight(_ highlighted: Bool) {
    let effectiveHighlight = highlighted && hoverHighlightEnabled
    guard effectiveHighlight != isHoverHighlighted else { return }
    isHoverHighlighted = effectiveHighlight
    backgroundView.lbSetHoverHighlighted(effectiveHighlight, cornerRadius: hoverCornerRadius)
    hoverHighlightDidChange(effectiveHighlight)
  }

  private var usesMenuManagedHighlight: Bool {
    guard let item = enclosingMenuItem else { return false }
    return item.isEnabled && item.menu != nil
  }
}
