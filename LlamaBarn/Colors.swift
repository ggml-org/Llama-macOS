import AppKit

// Central place for custom colors that are not satisfied by system semantic colors.
// We prefer semantic/dynamic colors over hard-coding single HEX values so the UI
// adapts to light / dark appearances while keeping sufficient contrast.
extension NSColor {
  /// A greener, higher-contrast variant for tiny status chips & indicators.
  /// - Light appearance: darker, saturated green for readability on light bg.
  /// - Dark appearance: lighter, slightly desaturated green for readability on dark bg.
  static var llamaGreen: NSColor {
    let appearance = NSApplication.shared.effectiveAppearance
    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    if isDark {
      // ~#65D679 (adjusted to avoid neon while keeping contrast on dark backgrounds)
      return NSColor(calibratedRed: 0.40, green: 0.84, blue: 0.47, alpha: 1.0)
    } else {
      // ~#1F7F3A (darker than systemGreen for better legibility at 8pt)
      return NSColor(calibratedRed: 0.12, green: 0.50, blue: 0.23, alpha: 1.0)
    }
  }

  /// Border color for llamaGreen chips (subtle, dynamic alpha).
  static var llamaGreenBorder: NSColor { llamaGreen.withAlphaComponent(0.55) }

  // MARK: - LlamaBarn semantic roles (text)
  // Keep this intentionally small & map directly to platform semantic colors so updates are centralized.
  // Contrast ordering: primary > secondary > disabled.
  static var lbPrimaryText: NSColor { .labelColor }
  static var lbSecondaryText: NSColor { .secondaryLabelColor }
  static var lbDisabledText: NSColor {
    // Use tertiaryLabelColor but bump minimum alpha in dark mode to avoid illegibility.
    let base = NSColor.tertiaryLabelColor
    if NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
      return base.withAlphaComponent(max(base.alphaComponent, 0.55))
    }
    return base
  }

  static var lbSuccess: NSColor { llamaGreen }
  static var lbDestructive: NSColor { .systemRed }

  /// Subtle border / hairline separator for pills & chips.
  static var lbSubtleBorder: NSColor {
    // Derive from secondary text for predictable contrast; boosted light-mode alpha to avoid disappearing
    // on vibrancy backgrounds. We resolve the dynamic color at call-sites before converting to CGColor.
    let isDark =
      NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let alpha: CGFloat = isDark ? 0.30 : 0.26  // was 0.18 in light; raised to mitigate flicker/vanishing
    return lbSecondaryText.withAlphaComponent(alpha)
  }

  // Preferred semantic hover background for interactive rows.
  // Tuned for improved visibility in dark mode (prior neutralHoverBackground became too faint).
  // We keep neutralHoverBackground for backward compatibility (temporary) but migrate callers to this.
  static var lbHoverBackground: NSColor {
    // Neutral hover built from luminance overlays, not labelColor tint, so light/dark both look balanced.
    // Pattern: In light mode use a translucent black; in dark mode use a translucent white.
    // This mirrors system overlay design (e.g. iOS/macOS materials) and avoids muddy grays.
    let appearance = NSApplication.shared.effectiveAppearance
    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    let lightAlpha: CGFloat = increaseContrast ? 0.08 : 0.06  // black on light background
    let darkAlpha: CGFloat = increaseContrast ? 0.14 : 0.11  // white on dark background
    return
      (isDark
      ? NSColor.white.withAlphaComponent(darkAlpha) : NSColor.black.withAlphaComponent(lightAlpha))
  }
}
