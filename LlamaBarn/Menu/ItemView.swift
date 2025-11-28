import AppKit

/// Minimal base class for interactive menu items.
/// Provides a shared background container with selection highlight and a content area for subclasses.
///
/// Highlights work in two modes:
/// 1. Menu-managed: For enabled items in the root menu, highlights are controlled by
///    NSMenuDelegate.menu(_:willHighlight:). The highlight persists on parent items while their submenu is open.
/// 2. Self-managed: For disabled items (typical in submenus), uses NSTrackingArea to handle hover events.
///    This mode is necessary because the menu system only sends delegate callbacks for enabled items.
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
      if bounds.contains(localPoint) && !usesMenuManagedHighlight {
        setHighlight(true)
      }
    }
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    guard !usesMenuManagedHighlight else { return }
    // Early exit when highlight is disabled - avoids unnecessary work compared to checking only in setHighlight
    guard highlightEnabled else { return }
    setHighlight(true)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    guard !usesMenuManagedHighlight else { return }
    setHighlight(false)
  }

  /// Programmatically set selection highlight.
  /// Used by MenuController for menu-managed highlights and internally for self-managed hover.
  func setHighlight(_ highlighted: Bool) {
    let shouldHighlight = highlighted && highlightEnabled
    guard shouldHighlight != isHighlighted else { return }
    isHighlighted = shouldHighlight
    backgroundView.setHighlight(shouldHighlight, cornerRadius: Layout.cornerRadius)
    highlightDidChange(shouldHighlight)
  }

  /// Returns true if this view's highlight is managed by NSMenuDelegate.menu(_:willHighlight:).
  /// Only enabled items in menus trigger delegate callbacks, so disabled items
  /// (like submenu model items) handle their own hover via tracking areas.
  private var usesMenuManagedHighlight: Bool {
    guard let item = enclosingMenuItem else { return false }
    return item.isEnabled && item.menu != nil
  }
}
