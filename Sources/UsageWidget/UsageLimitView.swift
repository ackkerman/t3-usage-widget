import SwiftUI
import UsageCore
import WidgetKit

/// Displays remaining allowance and the next reset rather than the used percentage.
public struct UsageLimitView: View {
  public let snapshot: UsageSnapshot
  public let family: WidgetFamily

  public init(snapshot: UsageSnapshot, family: WidgetFamily) {
    self.snapshot = snapshot
    self.family = family
  }

  private var capacity: Int {
    switch family {
    case .systemLarge: return 4
    case .systemMedium: return 2
    default: return 1
    }
  }

  public var body: some View {
    if snapshot.limits.isEmpty {
      Text(UsageStrings.text(.limitsUnavailable, language: snapshot.language)).font(.caption)
        .foregroundStyle(.secondary)
    } else {
      VStack(alignment: .leading, spacing: family == .systemLarge ? 7 : 4) {
        ForEach(Array(snapshot.limits.prefix(capacity))) { limit in
          let remaining = max(0, min(100, 100 - limit.usedPercent))
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
              Text(limit.displayLabel(language: snapshot.language)).lineLimit(1).truncationMode(
                .tail)
              Spacer(minLength: 0)
              Text(
                UsageStrings.text(
                  .remaining, language: snapshot.language, String(Int(remaining.rounded())))
              ).fixedSize().layoutPriority(1)
            }.font(.system(size: family == .systemSmall ? 9 : 10))
            ProgressView(value: remaining, total: 100)
              .tint(
                limit.label.lowercased().contains("claude")
                  ? UsagePalette.provider("claude") : .gray
              )
              .accessibilityLabel(
                Text(
                  UsageStrings.text(
                    .remainingAccessibility, language: snapshot.language,
                    limit.displayLabel(language: snapshot.language),
                    String(Int(remaining.rounded())))))
            if family == .systemLarge {
              HStack(spacing: 4) {
                if let date = limit.resetsAt {
                  Text(UsageStrings.text(.reset, language: snapshot.language))
                    + Text(date, style: .relative)
                }
                if let credits = limit.resetCreditCount, credits > 0 {
                  Text(
                    UsageStrings.text(.resetCredits, language: snapshot.language, String(credits)))
                }
              }.font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            }
          }
        }
        if snapshot.limits.count > capacity && family != .systemSmall {
          Text(
            UsageStrings.text(
              .moreCount, language: snapshot.language, String(snapshot.limits.count - capacity))
          ).font(.caption2).foregroundStyle(
            .secondary)
        }
      }
    }
  }
}
