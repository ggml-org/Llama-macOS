import AppKit

/// Shared UI layout constants and helpers for NSMenu custom rows.
enum Layout {
  /// Distance from menu edge to background view (used in all menu items and headers).
  static let outerHorizontalPadding: CGFloat = 5
  /// Distance from background edge to content (used in all menu items and headers).
  static let innerHorizontalPadding: CGFloat = 8
  /// Vertical spacing between content and background edge (used in ItemView).
  static let verticalPadding: CGFloat = 4
  /// Rounded corner radius for highlights.
  static let cornerRadius: CGFloat = 6
  /// Size for icons (model icons, status indicators, chevrons, cancel buttons).
  static let iconSize: CGFloat = 16
  /// Maximum width for download progress labels.
  static let progressWidth: CGFloat = 48
}

extension NSView {
  /// Applies or clears the standard selection highlight background on a container view.
  /// Uses dynamic colors resolved for the view's effective appearance and sets a rounded corner.
  func setHighlight(_ highlighted: Bool, cornerRadius: CGFloat = Layout.cornerRadius) {
    wantsLayer = true
    let color: NSColor = highlighted ? .lbSubtleBackground : .clear
    layer?.setBackgroundColor(color, in: self)
    layer?.cornerRadius = cornerRadius
  }
}

extension NSMenuItem {
  /// Creates a disabled NSMenuItem backed by a custom view and optional minimum height.
  static func viewItem(with view: NSView, minHeight: CGFloat? = nil) -> NSMenuItem {
    let item = NSMenuItem()
    item.isEnabled = false
    item.view = view
    if let minHeight {
      view.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true
    }
    return item
  }
}
