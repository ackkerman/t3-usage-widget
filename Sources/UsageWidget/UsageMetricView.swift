import SwiftUI
import UsageCore
import WidgetKit

/// Combines a headline, provider breakdown, trend and token/cost categories for one selected metric.
public struct UsageMetricView: View {
  public let snapshot: UsageSnapshot
  public let metric: UsageTab
  public let family: WidgetFamily

  public init(snapshot: UsageSnapshot, metric: UsageTab, family: WidgetFamily) {
    self.snapshot = snapshot
    self.metric = metric
    self.family = family
  }

  private var headline: String {
    metric == .tokens
      ? UsageFormatting.tokens(snapshot.processedTokens)
      : UsageFormatting.cost(snapshot.estimatedCostUSD)
  }
  private var unit: String {
    UsageStrings.text(
      metric == .tokens
        ? .tokensUnit : (snapshot.hasUnpricedUsage ? .unpricedExcluded : .apiEstimate),
      language: snapshot.language)
  }
  private var rankedProviders: [UsageProviderSummary] {
    snapshot.providers.sorted { a, b in
      if metric == .tokens { return a.processedTokens > b.processedTokens }
      return (a.estimatedCostUSD ?? -1) > (b.estimatedCostUSD ?? -1)
    }
  }

  public var body: some View {
    if family == .systemLarge {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 4) {
            Text(headline).font(.system(size: 22, weight: .semibold)).lineLimit(1)
              .minimumScaleFactor(0.65)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
            ForEach(Array(rankedProviders.prefix(3))) { provider in
              ProviderSummaryRow(
                provider: provider, metric: metric, totalTokens: snapshot.processedTokens,
                totalCost: snapshot.estimatedCostUSD, language: snapshot.language)
            }
            if rankedProviders.count > 3 {
              Text(
                UsageStrings.text(
                  .moreCount, language: snapshot.language, String(rankedProviders.count - 3))
              ).font(.caption2).foregroundStyle(.secondary)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
          VStack(alignment: .leading, spacing: 3) {
            Text(
              UsageStrings.text(
                snapshot.period == .day
                  ? (metric == .tokens ? .hourlyTokens : .hourlyCost)
                  : (metric == .tokens ? .dailyTokens : .dailyCost), language: snapshot.language)
            ).font(.caption2)
            UsageSeriesChart(snapshot: snapshot, metric: metric, compact: false)
          }.frame(maxWidth: .infinity)
        }.frame(height: 150)
        if let categories = snapshot.categories {
          HStack(spacing: 5) {
            Text(
              UsageStrings.text(
                .cachedValue, language: snapshot.language,
                UsageFormatting.tokens(categories.cacheRead)))
            Text(
              UsageStrings.text(
                .inputValue, language: snapshot.language, UsageFormatting.tokens(categories.input)))
            Text(
              UsageStrings.text(
                .outputValue, language: snapshot.language, UsageFormatting.tokens(categories.output)
              ))
          }.font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
          if let savings = categories.cacheSavingsUSD {
            Text(
              UsageStrings.text(
                .cacheSavings, language: snapshot.language, UsageFormatting.cost(savings))
            )
            .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
          }
          UsageCategoryBar(categories: categories, metric: metric, language: snapshot.language)
        }
      }
    } else {
      HStack(alignment: .top, spacing: 6) {
        VStack(alignment: .leading, spacing: 2) {
          Text(headline).font(.system(size: family == .systemSmall ? 17 : 20, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.6)
          Text(unit).font(.system(size: 9)).foregroundStyle(.secondary)
          if family == .systemMedium, let first = rankedProviders.first {
            ProviderSummaryRow(
              provider: first, metric: metric, totalTokens: snapshot.processedTokens,
              totalCost: snapshot.estimatedCostUSD, language: snapshot.language)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
        if family != .systemSmall {
          UsageSeriesChart(snapshot: snapshot, metric: metric, compact: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      if family == .systemSmall {
        UsageSeriesChart(snapshot: snapshot, metric: metric, compact: true)
          .frame(maxHeight: .infinity)
      }
    }
  }
}

private struct ProviderSummaryRow: View {
  let provider: UsageProviderSummary
  let metric: UsageTab
  let totalTokens: Int64?
  let totalCost: Double?
  let language: UsageLanguage

  private var share: Double? {
    if metric == .tokens, let totalTokens, totalTokens > 0 {
      return Double(provider.processedTokens) / Double(totalTokens) * 100
    }
    if metric == .cost, let totalCost, totalCost > 0, let value = provider.estimatedCostUSD {
      return value / totalCost * 100
    }
    return nil
  }

  var body: some View {
    HStack(spacing: 3) {
      Circle().fill(UsagePalette.provider(provider.id)).frame(width: 5, height: 5)
      Text(provider.displayName).lineLimit(1).truncationMode(.tail)
      Spacer(minLength: 0)
      Text(
        metric == .tokens
          ? UsageFormatting.tokens(provider.processedTokens)
          : UsageFormatting.cost(provider.estimatedCostUSD)
      )
      .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
    }.font(.system(size: 9))
    HStack(spacing: 3) {
      if let sessions = provider.sessions {
        Text(UsageStrings.text(.sessions, language: language, String(sessions)))
      }
      if let share { Text(String(format: "%.1f%%", share)) }
    }.font(.system(size: 8)).foregroundStyle(.secondary)
  }
}
