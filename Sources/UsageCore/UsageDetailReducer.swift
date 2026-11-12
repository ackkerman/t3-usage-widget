import Foundation

/// Produces the chart and category totals from the same buckets as the headline totals.
enum UsageDetailReducer {
  private struct Key: Hashable {
    let period: String
    let provider: String
  }
  private struct Aggregate {
    var tokens: Int64 = 0
    var cost: Double = 0
    var unknownCost = false
  }

  static func sessions(for provider: String, sources: [Source]) -> Int? {
    var seen = Set<SourceFingerprint>()
    var total = 0
    var found = false
    for source in sources {
      guard source.status != "missing", let fingerprint = source.fingerprint,
        fingerprint.provider == provider, let count = source.distinctSessions,
        seen.insert(fingerprint).inserted
      else { continue }
      total += count
      found = true
    }
    return found ? total : nil
  }

  static func series(_ buckets: [Bucket], pricingAvailable: Bool) -> [UsageSeriesPoint] {
    var values: [Key: Aggregate] = [:]
    for bucket in buckets {
      guard let period = bucket.hourStart ?? bucket.day else { continue }
      let key = Key(period: period, provider: bucket.provider)
      var value = values[key, default: Aggregate()]
      value.tokens += bucket.totals.uncachedInputTokens + bucket.totals.cachedInputTokens
      value.tokens += bucket.totals.cacheCreationTokens + bucket.totals.outputTokens
      value.cost += bucket.costUsd
      value.unknownCost = value.unknownCost || bucket.unpricedRecords > 0 || !pricingAvailable
      values[key] = value
    }
    var result: [UsageSeriesPoint] = []
    for (key, value) in values {
      result.append(
        UsageSeriesPoint(
          period: key.period, provider: key.provider,
          processedTokens: value.tokens, estimatedCostUSD: value.unknownCost ? nil : value.cost))
    }
    return result.sorted { a, b in
      a.period == b.period ? a.provider < b.provider : a.period < b.period
    }
  }

  static func categories(_ buckets: [Bucket], hasData: Bool, costAvailable: Bool)
    -> UsageCategories?
  {
    guard hasData else { return nil }
    var input: Int64 = 0
    var read: Int64 = 0
    var write: Int64 = 0
    var output: Int64 = 0
    var inputCost = 0.0
    var readCost = 0.0
    var writeCost = 0.0
    var outputCost = 0.0
    var savings = 0.0
    var hasAllCosts = costAvailable
    var hasAllSavings = true
    for bucket in buckets {
      input += bucket.totals.uncachedInputTokens
      read += bucket.totals.cachedInputTokens
      write += bucket.totals.cacheCreationTokens
      output += bucket.totals.outputTokens
      if let c = bucket.categoryCostUsd {
        inputCost += c.input
        readCost += c.cacheRead
        writeCost += c.cacheWrite
        outputCost += c.output
      } else {
        hasAllCosts = false
      }
      if let value = bucket.cacheSavingsUsd { savings += value } else { hasAllSavings = false }
    }
    return UsageCategories(
      input: input, cacheRead: read, cacheWrite: write, output: output,
      inputCost: hasAllCosts ? inputCost : nil, cacheReadCost: hasAllCosts ? readCost : nil,
      cacheWriteCost: hasAllCosts ? writeCost : nil, outputCost: hasAllCosts ? outputCost : nil,
      cacheSavingsUSD: hasAllSavings ? savings : nil)
  }
}
