import SwiftUI
import UsageCore
import WidgetKit

private struct UsageEntry: TimelineEntry {
  let date: Date
  let snapshot: UsageSnapshot
  let isSample: Bool

  static var sample: UsageEntry {
    let now = Date()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    var series: [UsageSeriesPoint] = []
    for index in 0..<7 {
      guard let day = Calendar.current.date(byAdding: .day, value: index - 6, to: now) else {
        continue
      }
      let date = formatter.string(from: day)
      series.append(
        UsageSeriesPoint(
          period: date, provider: "codex", processedTokens: Int64((index + 2) * 3_000_000),
          estimatedCostUSD: Double(index + 2) * 0.3))
      series.append(
        UsageSeriesPoint(
          period: date, provider: "claude", processedTokens: Int64((7 - index) * 1_000_000),
          estimatedCostUSD: Double(7 - index) * 0.2))
    }
    return UsageEntry(
      date: now,
      snapshot: UsageSnapshot(
        processedTokens: 125_000_000, estimatedCostUSD: 12.34,
        limits: [
          UsageLimit(
            id: "sample-1", label: "Codex Weekly", usedPercent: 35,
            resetsAt: now.addingTimeInterval(3600 * 72), resetCreditCount: 2, providerName: "Codex",
            windowName: "Weekly")!,
          UsageLimit(
            id: "sample-2", label: "Claude Session", usedPercent: 20,
            resetsAt: now.addingTimeInterval(3600), providerName: "Claude", windowName: "Session")!,
          UsageLimit(
            id: "sample-3", label: "Claude Weekly", usedPercent: 42,
            resetsAt: now.addingTimeInterval(3600 * 120), providerName: "Claude",
            windowName: "Weekly")!,
        ],
        updatedAt: now, status: .connected,
        providers: [
          UsageProviderSummary(
            id: "codex", processedTokens: 90_000_000, estimatedCostUSD: 8.4, sessions: 55),
          UsageProviderSummary(
            id: "claude", processedTokens: 35_000_000, estimatedCostUSD: 3.94, sessions: 31),
        ], series: series,
        categories: UsageCategories(
          input: 4_000_000, cacheRead: 115_000_000,
          cacheWrite: 1_000_000, output: 5_000_000, inputCost: 2, cacheReadCost: 7.34,
          cacheWriteCost: 1, outputCost: 2, cacheSavingsUSD: 200)),
      isSample: true)
  }

}

private struct UsageTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> UsageEntry {
    let preview = UsageEntry.sample
    return UsageEntry(
      date: preview.date,
      snapshot: preview.snapshot.withLanguage(LocalSnapshotClient.cachedLanguage()), isSample: true)
  }

  func getSnapshot(in context: Context, completion: @escaping @Sendable (UsageEntry) -> Void) {
    if context.isPreview {
      Task {
        let current = await LocalSnapshotClient.read(timeout: 1)
        let preview = UsageEntry.sample
        completion(
          UsageEntry(
            date: preview.date, snapshot: preview.snapshot.withLanguage(current.language),
            isSample: true))
      }
    } else {
      Task {
        completion(
          UsageEntry(date: .now, snapshot: await LocalSnapshotClient.read(), isSample: false))
      }
    }
  }

  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<UsageEntry>) -> Void
  ) {
    Task {
      let now = Date()
      let snapshot = await LocalSnapshotClient.read()
      var entries = [UsageEntry(date: now, snapshot: snapshot, isSample: false)]
      if let expiry = LocalSnapshotClient.expiration(of: snapshot, now: now) {
        entries.append(
          UsageEntry(
            date: expiry,
            snapshot: .disconnected.selecting(snapshot.tab).withLanguage(snapshot.language),
            isSample: false))
      }
      completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
  }
}

private struct UsageWidgetView: View {
  let snapshot: UsageSnapshot
  let isSample: Bool
  @Environment(\.widgetFamily) private var family

  var body: some View {
    VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 6) {
      UsageTabBar(selected: snapshot.tab, family: family, language: snapshot.language)
      if snapshot.tab != .limits && snapshot.status != .disconnected {
        UsagePeriodBar(selected: snapshot.period, family: family, language: snapshot.language)
      }
      if snapshot.status == .loading {
        VStack(alignment: .leading, spacing: 10) {
          Text(UsageStrings.text(.loading, language: snapshot.language)).font(.caption)
            .foregroundStyle(.secondary)
          RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.18))
            .frame(width: 90, height: 18)
          RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.12))
            .frame(maxWidth: .infinity).frame(height: family == .systemSmall ? 35 : 55)
        }.accessibilityElement(children: .ignore).accessibilityLabel(
          Text(UsageStrings.text(.loadingAccessibility, language: snapshot.language)))
      } else if snapshot.status == .disconnected {
        Text(UsageStrings.text(.disconnected, language: snapshot.language)).font(.subheadline)
        Text(UsageStrings.text(.openApp, language: snapshot.language)).font(.caption2)
          .foregroundStyle(.secondary)
      } else {
        HStack {
          Text(
            isSample
              ? UsageStrings.text(.sample, language: snapshot.language)
              : UsageStrings.text(
                snapshot.includesRemote ? .connectedEnvironments : .thisMac,
                language: snapshot.language)
          )
          Spacer()
          if snapshot.status == .partial {
            Text(UsageStrings.text(.partialShort, language: snapshot.language))
          }
        }.font(.system(size: 8)).foregroundStyle(.secondary)
        if snapshot.tab == .limits {
          UsageLimitView(snapshot: snapshot, family: family)
        } else {
          UsageMetricView(snapshot: snapshot, metric: snapshot.tab, family: family)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .environment(\.locale, snapshot.language.locale)
    .containerBackground(for: .widget) { Color.clear }
  }
}

/// Widget configuration is compiled as a library until a signed host app embeds it.
public struct T3UsageWidget: Widget {
  public init() {}
  public var body: some WidgetConfiguration {
    StaticConfiguration(kind: "T3UsageWidget", provider: UsageTimelineProvider()) { entry in
      UsageWidgetView(snapshot: entry.snapshot, isSample: entry.isSample)
    }
    .configurationDisplayName("T3 Usage")
    .description(
      Text(UsageStrings.text(.widgetDescription, language: LocalSnapshotClient.cachedLanguage()))
    )
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
