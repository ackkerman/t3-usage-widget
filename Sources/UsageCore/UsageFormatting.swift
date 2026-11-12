import Foundation

/// Formatting keeps unavailable values distinct from measured zero.
public enum UsageFormatting {
  public static func tokens(_ value: Int64?) -> String {
    guard let value, value >= 0 else { return "—" }
    let number = Double(value)
    for (threshold, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")] {
      if number >= threshold {
        return String(
          format: "%.1f%@", locale: Locale(identifier: "en_US_POSIX"), number / threshold, suffix)
      }
    }
    return String(value)
  }

  public static func cost(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "—" }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.currencySymbol = "$"
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? "—"
  }
}
