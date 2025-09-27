import AppKit

/// Shared UI metrics and helpers for NSMenu custom rows.
enum MenuMetrics {
  static let outerHorizontalPadding: CGFloat = 5
  static let innerHorizontalPadding: CGFloat = 8
  static let verticalPadding: CGFloat = 4
  static let cornerRadius: CGFloat = 6
  // Visual size for small inline glyphs.
  static let iconSize: CGFloat = 16
  // Circular badge container size for leading model icon (closer to Wi‑Fi menu).
  static let iconBadgeSize: CGFloat = 28
  static let smallIconSize: CGFloat = 18
  static let progressWidth: CGFloat = 48
}

/// Shared type ramp for menu rows.
enum MenuTypography {
  static let primary = NSFont.systemFont(ofSize: 13)
  // Secondary/line-2 text used across rows (variants, installed, family) for consistency
  static let secondary = NSFont.systemFont(ofSize: 11, weight: .regular)
}

extension NSView {
  /// Applies or clears the standard hover highlight background on a container view.
  /// Uses dynamic colors resolved for the view’s effective appearance and sets a rounded corner.
  func lbSetHoverHighlighted(_ highlighted: Bool, cornerRadius: CGFloat = MenuMetrics.cornerRadius)
  {
    wantsLayer = true
    let color: NSColor = highlighted ? .lbHoverBackground : .clear
    layer?.backgroundColor = NSColor.cgColor(color, in: self)
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
