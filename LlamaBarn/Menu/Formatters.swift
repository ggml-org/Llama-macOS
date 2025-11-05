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

  // MARK: - Date Formatting

  /// Cached medium style date formatter for UI labels.
  private static let mediumDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .none
    return df
  }()

  /// Cached month and year style date formatter for UI labels.
  private static let monthYearFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "MMM yyyy"
    return df
  }()

  static func date(_ date: Date) -> String {
    mediumDateFormatter.string(from: date)
  }

  static func monthYear(_ date: Date) -> String {
    monthYearFormatter.string(from: date)
  }

  // MARK: - Token Formatting (binary: 1k = 1024)

  /// Formats token counts using binary units (1k = 1024).
  /// Examples: 131_072 → "128k", 262_144 → "256k", 32_768 → "32k"
  /// Uses binary units since context windows represent memory allocation.
  static func tokens(_ tokens: Int) -> String {
    if tokens >= 1_048_576 {
      return String(format: "%.0fm", Double(tokens) / 1_048_576.0)
    } else if tokens >= 10_240 {
      return String(format: "%.0fk", Double(tokens) / 1_024.0)
    } else if tokens >= 1_024 {
      return String(format: "%.1fk", Double(tokens) / 1_024.0)
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

  /// Formats runtime memory usage from binary megabytes.
  /// Shows MB when < 1 GB, otherwise GB with appropriate precision.
  /// Uses binary units (1 GB = 1024 MB) to match Activity Monitor.
  static func memoryRuntime(mb: Double) -> String? {
    guard mb > 0 else { return nil }
    if mb >= 1024 {
      let gb = mb / 1024
      return gb < 10 ? String(format: "%.1f GB", gb) : String(format: "%.0f GB", gb)
    }
    return String(format: "%.0f MB", mb)
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
  static func progress(_ progress: Progress) -> Int {
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
  static func modelMetadata(for model: CatalogEntry) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let usableCtx = Catalog.usableCtxWindow(for: model)

    // Size
    result.append(
      NSAttributedString(string: model.totalSize, attributes: Typography.secondaryAttributes))
    result.append(MetadataLabel.makeSeparator())

    // Memory (estimated)
    let memoryMb = Catalog.runtimeMemoryUsageMb(
      for: model,
      ctxWindowTokens: Double(usableCtx ?? model.ctxWindow)
    )
    result.append(
      NSAttributedString(
        string: Format.memory(mb: memoryMb) + " mem",
        attributes: Typography.secondaryAttributes))
    result.append(MetadataLabel.makeSeparator())

    // Context window: show usable value if limited by memory, otherwise show full value
    if let usable = usableCtx, usable < model.ctxWindow {
      let text = Format.tokens(usable) + " ctx"
      result.append(NSAttributedString(string: text, attributes: Typography.secondaryAttributes))
    } else {
      if model.ctxWindow > 0 {
        let text = Format.tokens(model.ctxWindow) + " ctx"
        result.append(NSAttributedString(string: text, attributes: Typography.secondaryAttributes))
      } else {
        result.append(NSAttributedString(string: "—", attributes: Typography.secondaryAttributes))
      }
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
