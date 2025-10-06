import AppKit
import Foundation

enum ByteFormatters {
  /// Formats bytes as decimal gigabytes with two fractional digits (e.g., "3.14 GB").
  /// Uses 1 GB = 1,000,000,000 bytes to match network/download UI conventions.
  static func gbTwoDecimals(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000.0
    return String(format: "%.2f GB", gb)
  }

  /// Cached ByteCountFormatter for decimal GB formatting.
  /// Formatters are expensive to create (system locale lookups, number formatting setup).
  /// Since we call this repeatedly during menu display and status updates, caching the formatter
  /// eliminates this overhead. Follows the same pattern as DateFormatters below.
  private static let decimalGB: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB]
    formatter.countStyle = .decimal
    return formatter
  }()

  /// Formats byte count as decimal GB using cached formatter (e.g., "3.14 GB").
  /// Uses 1 GB = 1,000,000,000 bytes to match network/download UI conventions.
  static func decimalGB(_ bytes: Int64) -> String {
    decimalGB.string(fromByteCount: bytes)
  }
}

enum DateFormatters {
  /// Cached medium style date formatter for UI labels.
  private static let medium: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .none
    return df
  }()

  /// Cached month and year style date formatter for UI labels.
  private static let monthAndYear: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "MMM yyyy"
    return df
  }()

  static func medium(_ date: Date) -> String { medium.string(from: date) }

  static func monthAndYear(_ date: Date) -> String { monthAndYear.string(from: date) }
}

enum TokenFormatters {
  /// Formats token counts like 262_144 as "262k" or "32k" for UI chips.
  static func shortTokens(_ tokens: Int) -> String {
    if tokens >= 1_000_000 {
      return String(format: "%.0fm", Double(tokens) / 1_000_000.0)
    } else if tokens >= 10_000 {
      return String(format: "%.0fk", Double(tokens) / 1_000.0)
    } else if tokens >= 1_000 {
      return String(format: "%.1fk", Double(tokens) / 1_000.0)
    } else {
      return "\(tokens)"
    }
  }
}

enum MemoryFormatters {
  /// Formats binary megabytes as gigabytes with one decimal (e.g., "3.1 GB" from 3174 MB).
  /// Uses binary units (1 GB = 1024 MB) to match Activity Monitor and system memory reporting.
  static func gbOneDecimal(_ mb: UInt64) -> String {
    let gb = Double(mb) / 1024.0
    return String(format: "%.1f GB", gb)
  }

  /// Formats runtime memory usage from binary megabytes.
  /// Shows MB when < 1 GB, otherwise GB with appropriate precision.
  /// Uses binary units (1 GB = 1024 MB) to match Activity Monitor.
  static func runtime(_ mb: Double) -> String? {
    guard mb > 0 else { return nil }
    if mb >= 1024 {
      let gb = mb / 1024
      return gb < 10 ? String(format: "%.1f GB", gb) : String(format: "%.0f GB", gb)
    }
    return String(format: "%.0f MB", mb)
  }
}

enum QuantizationFormatters {
  /// Extracts the first segment of a quantization label for compact display.
  /// Examples: "Q4_K_M" → "Q4", "Q8_0" → "Q8", "F16" → "F16"
  static func short(_ quantization: String) -> String {
    let upper = quantization.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !upper.isEmpty else { return upper }
    if let idx = upper.firstIndex(where: { $0 == "_" || $0 == "-" }) {
      let prefix = upper[..<idx]
      if !prefix.isEmpty { return String(prefix) }
    }
    return upper
  }
}

enum ProgressFormatters {
  /// Calculates download progress percentage from a Progress object.
  /// Returns 0 if totalUnitCount is 0 or invalid, otherwise percentage 0-100.
  static func percent(_ progress: Progress) -> Int {
    guard progress.totalUnitCount > 0 else { return 0 }
    let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
    return max(0, min(100, Int(fraction * 100)))
  }

  /// Formats progress percentage as a string (e.g., "42%").
  static func percentText(_ progress: Progress) -> String {
    "\(percent(progress))%"
  }
}

enum ModelMetadataFormatters {
  /// Formats complete model metadata line showing size, memory, and context window.
  /// Format: "􀥾 2.53 GB • 􀫦 3.1 GB • 􀵫 128k" (or "􀵫 ~~128k~~ 32k" if capped).
  static func makeMetadataText(for model: CatalogEntry) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let usableCtx = Catalog.usableCtxWindow(for: model)

    // Size
    result.append(MetadataLabel.make(icon: MetadataLabel.sizeSymbol, text: model.totalSize))
    result.append(MetadataLabel.makeSeparator())

    // Memory (estimated)
    let memoryMb = Catalog.runtimeMemoryUsageMb(
      for: model,
      ctxWindowTokens: Double(usableCtx ?? model.ctxWindow)
    )
    result.append(
      MetadataLabel.make(
        icon: MetadataLabel.memorySymbol, text: MemoryFormatters.gbOneDecimal(memoryMb)))
    result.append(MetadataLabel.makeSeparator())

    // Context window: strikethrough if capped, normal otherwise
    if let usable = usableCtx, usable < model.ctxWindow {
      result.append(MetadataLabel.makeIconOnly(icon: MetadataLabel.contextSymbol))
      result.append(NSAttributedString(string: " "))
      var attrs = Typography.secondaryAttributes
      attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
      result.append(
        NSAttributedString(
          string: TokenFormatters.shortTokens(model.ctxWindow), attributes: attrs))
      result.append(NSAttributedString(string: " ", attributes: Typography.secondaryAttributes))
      result.append(
        NSAttributedString(
          string: TokenFormatters.shortTokens(usable), attributes: Typography.secondaryAttributes))
    } else {
      let text = model.ctxWindow > 0 ? TokenFormatters.shortTokens(model.ctxWindow) : "—"
      result.append(MetadataLabel.make(icon: MetadataLabel.contextSymbol, text: text))
    }

    return result
  }
}
