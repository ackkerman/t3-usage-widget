import Foundation

/// Turns a single environment's response into display values without inventing zero data.
enum UsageSummaryReducer {
  static func snapshot(
    _ usage: UsageResponse, limits: [UsageLimit], updatedAt: Date, period: UsagePeriod = .month
  )
    throws -> UsageSnapshot
  {
    guard (4...6).contains(usage.contractVersion) else {
      throw ClientError.unsupportedContract(usage.contractVersion)
    }
    let hasReadableSource = usage.sources.contains { $0.status == "ok" || $0.status == "partial" }
    let hasData = hasReadableSource || !usage.buckets.isEmpty
    let tokens = usage.buckets.reduce(Int64(0)) { sum, bucket in
      sum + bucket.totals.uncachedInputTokens + bucket.totals.cachedInputTokens
        + bucket.totals.cacheCreationTokens + bucket.totals.outputTokens
    }
    let cost = usage.buckets.reduce(0.0) { $0 + $1.costUsd }
    let grouped = Dictionary(grouping: usage.buckets, by: \.provider)
    var providers: [UsageProviderSummary] = []
    for (name, buckets) in grouped {
      var providerTokens: Int64 = 0
      var providerCost: Double = 0
      var unknown = usage.pricing.status == "unavailable"
      for bucket in buckets {
        providerTokens += bucket.totals.uncachedInputTokens
        providerTokens += bucket.totals.cachedInputTokens
        providerTokens += bucket.totals.cacheCreationTokens
        providerTokens += bucket.totals.outputTokens
        providerCost += bucket.costUsd
        if bucket.unpricedRecords > 0 { unknown = true }
      }
      let cost: Double? =
        usage.pricing.status == "unavailable" || (unknown && providerCost == 0)
        ? nil : providerCost
      let sessions = UsageDetailReducer.sessions(for: name, sources: usage.sources)
      providers.append(
        UsageProviderSummary(
          id: name, processedTokens: providerTokens, estimatedCostUSD: cost, sessions: sessions))
    }
    providers.sort { a, b in
      if a.processedTokens == b.processedTokens { return a.id < b.id }
      return a.processedTokens > b.processedTokens
    }
    let costUnavailable =
      usage.pricing.status == "unavailable" || usage.buckets.contains { $0.unpricedRecords > 0 }
    let partial =
      !hasData || costUnavailable
      || usage.sources.contains { $0.status != "ok" && $0.status != "missing" }
    return UsageSnapshot(
      processedTokens: hasData ? tokens : nil,
      estimatedCostUSD: hasData && usage.pricing.status != "unavailable"
        && (!costUnavailable || cost > 0) ? cost : nil,
      limits: limits,
      updatedAt: updatedAt,
      status: partial ? .partial : .connected,
      period: period,
      providers: providers,
      series: UsageDetailReducer.series(
        usage.buckets, pricingAvailable: usage.pricing.status != "unavailable"),
      categories: UsageDetailReducer.categories(
        usage.buckets, hasData: hasData, costAvailable: !costUnavailable),
      hasUnpricedUsage: usage.buckets.contains { $0.unpricedRecords > 0 }
    )
  }
}
