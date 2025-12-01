import AppKit
import Foundation

enum Format {
  // MARK: - Byte Formatting (decimal: 1 GB = 1e9 bytes)

  /// Formats bytes as decimal gigabytes with one fractional digit (e.g., "3.1 GB").
  /// Omits decimal point when fractional part is zero (e.g., "4 GB" not "4.0 GB").
  /// Uses 1 GB = 1,000,000,000 bytes to match network/download UI conventions.
  /// Uses period separator (US format) for consistency with memory formatting.
  static func gigabytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000.0
    return gbOneDecimalString(gb)
  }

  // MARK: - Token Formatting (binary: 1k = 1024)

  /// Formats token counts using binary units (1k = 1024).
  /// Examples: 131_072 → "128k", 262_144 → "256k", 32_768 → "32k", 4_096 → "4k"
  /// Omits decimal point when fractional part is zero (e.g., "4k" not "4.0k").
  /// Uses binary units since context windows represent memory allocation.
  static func tokens(_ tokens: Int) -> String {
    if tokens >= 1_048_576 {
      let m = Double(tokens) / 1_048_576.0
      let format = tokens % 1_048_576 == 0 ? "%.0fm" : "%.1fm"
      return String(format: format, m)
    } else if tokens >= 10_240 {
      return String(format: "%.0fk", Double(tokens) / 1_024.0)
    } else if tokens >= 1_024 {
      let k = Double(tokens) / 1_024.0
      let format = tokens % 1_024 == 0 ? "%.0fk" : "%.1fk"
      return String(format: format, k)
    } else {
      return "\(tokens)"
    }
  }

  // MARK: - Memory Formatting (binary: 1 GB = 1024 MB)

  /// Formats binary megabytes as gigabytes with one decimal (e.g., "3.1 GB" from 3174 MB).
  /// Omits decimal point when fractional part is zero (e.g., "4 GB" not "4.0 GB").
  /// Uses binary units (1 GB = 1024 MB) to match Activity Monitor and system memory reporting.
  static func memory(mb: UInt64) -> String {
    let gb = Double(mb) / 1024.0
    return gbOneDecimalString(gb)
  }

  // MARK: - Metadata Formatting

  /// Creates a bullet separator for metadata lines (e.g., "2.5 GB · 128k · 4 GB").
  static func metadataSeparator() -> NSAttributedString {
    NSAttributedString(string: " · ", attributes: Typography.tertiaryAttributes)
  }

  // MARK: - Quantization Formatting

  /// Extracts the first segment of a quantization label for compact display.
  /// Examples: "Q4_K_M" → "Q4", "Q8_0" → "Q8", "F16" → "F16"
  static func quantization(_ label: String) -> String {
    let upper = label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !upper.isEmpty else { return upper }
    if let idx = upper.firstIndex(where: { $0 == "_" || $0 == "-" }) {
      let prefix = upper[..<idx]
      if !prefix.isEmpty { return String(prefix) }
    }
    return upper
  }

  // MARK: - Progress Formatting

  /// Calculates download progress percentage from a Progress object.
  /// Returns 0 if totalUnitCount is 0 or invalid, otherwise percentage 0-100.
  private static func progress(_ progress: Progress) -> Int {
    guard progress.totalUnitCount > 0 else { return 0 }
    let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
    return max(0, min(100, Int(fraction * 100)))
  }

  /// Formats progress percentage as a string (e.g., "42%").
  static func progressText(_ progress: Progress) -> String {
    "\(Format.progress(progress))%"
  }

  // MARK: - Model Metadata (composite)

  /// Formats model metadata text without icons (text only).
  /// Format: "2.53 GB · 3.1 GB mem · 128k ctx" (or "32k ctx capped" if limited).
  /// Vision models include " · vision" at the end.
  static func modelMetadata(
    for model: CatalogEntry,
    showMaxContext: Bool = false,
    activeContext: Int? = nil
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    let resolvedCtx: Int
    if let active = activeContext {
      resolvedCtx = active
    } else {
      resolvedCtx =
        Catalog.usableCtxWindow(for: model, maximizeContext: showMaxContext) ?? model.ctxWindow
    }

    // Size
    result.append(
      NSAttributedString(string: model.totalSize, attributes: Typography.secondaryAttributes))
    result.append(Format.metadataSeparator())

    // Memory (estimated)
    let memoryMb = Catalog.runtimeMemoryUsageMb(
      for: model,
      ctxWindowTokens: Double(resolvedCtx)
    )
    result.append(
      NSAttributedString(
        string: Format.memory(mb: memoryMb) + " mem",
        attributes: Typography.secondaryAttributes))
    result.append(Format.metadataSeparator())

    // Context window
    if resolvedCtx > 0 {
      let text = Format.tokens(resolvedCtx) + " ctx"
      result.append(NSAttributedString(string: text, attributes: Typography.secondaryAttributes))
    } else {
      result.append(NSAttributedString(string: "—", attributes: Typography.secondaryAttributes))
    }

    return result
  }

  /// Formats model name as "Family Size" with configurable colors.
  /// Used by both installed and catalog model item views.
  static func modelName(
    family: String,
    size: String,
    familyColor: NSColor,
    sizeColor: NSColor = Typography.secondaryColor
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()
    result.append(
      NSAttributedString(
        string: family, attributes: Typography.makePrimaryAttributes(color: familyColor)))
    result.append(
      NSAttributedString(
        string: " \(size)", attributes: Typography.makePrimaryAttributes(color: sizeColor)))
    return result
  }

  // MARK: - Private Helpers

  /// Formats a gigabyte value with one decimal place, omitting ".0" for whole numbers.
  private static func gbOneDecimalString(_ gb: Double) -> String {
    let rounded = (gb * 10).rounded() / 10
    let format = rounded.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f GB" : "%.1f GB"
    return String(format: format, rounded)
  }
}
