import AppKit

/// Minimal base class for interactive menu items.
/// Provides a shared background container with selection highlight and a content area for subclasses.
///
/// Uses NSTrackingArea to handle hover events for highlighting.
/// This is necessary because we use disabled NSMenuItems (to prevent menu closing on click),
/// which do not receive standard NSMenu highlighting events.
class ItemView: NSView {
  let backgroundView = NSView()
  let contentView = NSView()

  private var trackingArea: NSTrackingArea?
  private(set) var isHighlighted = false

  // MARK: - Customization hooks

  /// Override to disable selection highlight based on dynamic state (e.g., only when server is running).
  var highlightEnabled: Bool { true }
  /// Called whenever the selection highlight changes.
  func highlightDidChange(_ highlighted: Bool) {}

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    setupContainers()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setupContainers() {
    wantsLayer = true
    backgroundView.wantsLayer = true

    addSubview(backgroundView)
    backgroundView.addSubview(contentView)

    backgroundView.pinToSuperview(
      leading: Layout.outerHorizontalPadding,
      trailing: Layout.outerHorizontalPadding
    )
    contentView.pinToSuperview(
      top: Layout.verticalPadding,
      leading: Layout.innerHorizontalPadding,
      trailing: Layout.innerHorizontalPadding,
      bottom: Layout.verticalPadding
    )
  }

  // MARK: - Highlight handling

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
    addTrackingArea(trackingArea!)

    // Manually check if mouse is already inside to restore highlight immediately
    // (NSTrackingArea doesn't trigger mouseEntered if created while mouse is inside)
    if let window = window {
      let mouseLocation = window.mouseLocationOutsideOfEventStream
      let localPoint = convert(mouseLocation, from: nil)
      if bounds.contains(localPoint) {
        setHighlight(true)
      }
    }
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    setHighlight(true)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    setHighlight(false)
  }

  /// Programmatically set selection highlight.
  func setHighlight(_ highlighted: Bool) {
    let shouldHighlight = highlighted && highlightEnabled
    guard shouldHighlight != isHighlighted else { return }
    isHighlighted = shouldHighlight
    backgroundView.setHighlight(shouldHighlight, cornerRadius: Layout.cornerRadius)
    highlightDidChange(shouldHighlight)
  }

  // MARK: - Helpers

  /// Helper to add a click gesture recognizer to a view (defaults to self).
  @discardableResult
  func addGesture(
    to view: NSView? = nil,
    action: Selector,
    buttonMask: Int = 0x1
  ) -> NSClickGestureRecognizer {
    let targetView = view ?? self
    let click = NSClickGestureRecognizer(target: self, action: action)
    click.buttonMask = buttonMask
    targetView.addGestureRecognizer(click)
    return click
  }
}
