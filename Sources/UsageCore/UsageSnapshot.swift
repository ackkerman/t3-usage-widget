import Foundation

/// A display snapshot contains only values obtained from an authorized source.
/// Missing metrics remain nil so an unavailable value cannot be mistaken for zero.
public struct UsageSnapshot: Sendable, Equatable, Codable {
  public let processedTokens: Int64?
  public let estimatedCostUSD: Double?
  public let limits: [UsageLimit]
  public let updatedAt: Date?
  public let status: ConnectionStatus
  public let period: UsagePeriod
  public let providers: [UsageProviderSummary]
  public let series: [UsageSeriesPoint]
  public let categories: UsageCategories?
  public let tab: UsageTab
  public let language: UsageLanguage
  public let includesRemote: Bool
  public let hasUnpricedUsage: Bool

  public init(
    processedTokens: Int64?, estimatedCostUSD: Double?, limits: [UsageLimit], updatedAt: Date?,
    status: ConnectionStatus, period: UsagePeriod = .month, providers: [UsageProviderSummary] = [],
    series: [UsageSeriesPoint] = [], categories: UsageCategories? = nil, tab: UsageTab = .cost,
    language: UsageLanguage = .system, includesRemote: Bool = false, hasUnpricedUsage: Bool = false
  ) {
    self.processedTokens = processedTokens
    self.estimatedCostUSD = estimatedCostUSD
    self.limits = limits
    self.updatedAt = updatedAt
    self.status = status
    self.period = period
    self.providers = providers
    self.series = series
    self.categories = categories
    self.tab = tab
    self.language = language
    self.includesRemote = includesRemote
    self.hasUnpricedUsage = hasUnpricedUsage
  }

  public func selecting(_ tab: UsageTab) -> UsageSnapshot {
    UsageSnapshot(
      processedTokens: processedTokens, estimatedCostUSD: estimatedCostUSD,
      limits: limits, updatedAt: updatedAt, status: status, period: period,
      providers: providers, series: series, categories: categories, tab: tab, language: language,
      includesRemote: includesRemote, hasUnpricedUsage: hasUnpricedUsage)
  }

  public func withLanguage(_ language: UsageLanguage) -> UsageSnapshot {
    UsageSnapshot(
      processedTokens: processedTokens, estimatedCostUSD: estimatedCostUSD,
      limits: limits, updatedAt: updatedAt, status: status, period: period,
      providers: providers, series: series, categories: categories, tab: tab, language: language,
      includesRemote: includesRemote, hasUnpricedUsage: hasUnpricedUsage)
  }

  public func withStatus(_ status: ConnectionStatus) -> UsageSnapshot {
    UsageSnapshot(
      processedTokens: processedTokens, estimatedCostUSD: estimatedCostUSD,
      limits: limits, updatedAt: updatedAt, status: status, period: period,
      providers: providers, series: series, categories: categories, tab: tab, language: language,
      includesRemote: includesRemote, hasUnpricedUsage: hasUnpricedUsage)
  }

  public func includingRemote() -> UsageSnapshot {
    UsageSnapshot(
      processedTokens: processedTokens, estimatedCostUSD: estimatedCostUSD,
      limits: limits, updatedAt: updatedAt, status: status, period: period,
      providers: providers, series: series, categories: categories, tab: tab, language: language,
      includesRemote: true, hasUnpricedUsage: hasUnpricedUsage)
  }

  private enum CodingKeys: String, CodingKey {
    case processedTokens, estimatedCostUSD, limits, updatedAt, status, period, providers, series,
      categories, tab, language, includesRemote, hasUnpricedUsage
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      processedTokens: try values.decodeIfPresent(Int64.self, forKey: .processedTokens),
      estimatedCostUSD: try values.decodeIfPresent(Double.self, forKey: .estimatedCostUSD),
      limits: try values.decode([UsageLimit].self, forKey: .limits),
      updatedAt: try values.decodeIfPresent(Date.self, forKey: .updatedAt),
      status: try values.decode(ConnectionStatus.self, forKey: .status),
      period: try values.decode(UsagePeriod.self, forKey: .period),
      providers: try values.decode([UsageProviderSummary].self, forKey: .providers),
      series: try values.decode([UsageSeriesPoint].self, forKey: .series),
      categories: try values.decodeIfPresent(UsageCategories.self, forKey: .categories),
      tab: try values.decode(UsageTab.self, forKey: .tab),
      language: try values.decodeIfPresent(UsageLanguage.self, forKey: .language) ?? .system,
      includesRemote: try values.decodeIfPresent(Bool.self, forKey: .includesRemote) ?? false,
      hasUnpricedUsage: try values.decodeIfPresent(Bool.self, forKey: .hasUnpricedUsage) ?? false)
  }

  public static func loading(period: UsagePeriod, tab: UsageTab) -> UsageSnapshot {
    UsageSnapshot(
      processedTokens: nil, estimatedCostUSD: nil, limits: [], updatedAt: .now,
      status: .loading, period: period, tab: tab)
  }

  public static let disconnected = UsageSnapshot(
    processedTokens: nil, estimatedCostUSD: nil, limits: [], updatedAt: nil, status: .disconnected
  )
}

/// Describes whether a snapshot can be interpreted as current or incomplete.
public enum ConnectionStatus: Sendable, Equatable, Codable {
  case loading
  case connected
  case partial
  case disconnected
}

/// A provider limit describes the used share of a named time window.
public struct UsageLimit: Sendable, Equatable, Identifiable, Codable {
  public let id: String
  public let label: String
  public let usedPercent: Double
  public let resetsAt: Date?
  public let resetCreditCount: Int?
  public let providerName: String?
  public let windowName: String?

  public init?(
    id: String, label: String, usedPercent: Double, resetsAt: Date? = nil,
    resetCreditCount: Int? = nil, providerName: String? = nil, windowName: String? = nil
  ) {
    guard !id.isEmpty, !label.isEmpty, usedPercent.isFinite, (0...100).contains(usedPercent) else {
      return nil
    }
    self.id = id
    self.label = label
    self.usedPercent = usedPercent
    self.resetsAt = resetsAt
    self.resetCreditCount = resetCreditCount
    self.providerName = providerName
    self.windowName = windowName
  }

  public func displayLabel(language: UsageLanguage) -> String {
    guard let providerName, let windowName else { return label }
    for (prefix, key) in [
      ("Weekly", UsageStrings.Key.weekly), ("Session", .session), ("Monthly", .monthly),
    ] {
      if windowName == prefix || windowName.hasPrefix(prefix + " ·") {
        return providerName + " " + UsageStrings.text(key, language: language)
          + windowName.dropFirst(prefix.count)
      }
    }
    return providerName + " " + windowName
  }
}

/// Summarizes one provider; an unknown cost is never represented as zero.
public struct UsageProviderSummary: Sendable, Equatable, Codable, Identifiable {
  public let id: String
  public let processedTokens: Int64
  public let estimatedCostUSD: Double?
  public let sessions: Int?

  public init(id: String, processedTokens: Int64, estimatedCostUSD: Double?, sessions: Int? = nil) {
    self.id = id
    self.processedTokens = processedTokens
    self.estimatedCostUSD = estimatedCostUSD
    self.sessions = sessions
  }

  public var displayName: String {
    switch id {
    case "codex": return "Codex"
    case "claude": return "Claude Code"
    case "grok": return "Grok"
    case "cursor": return "Cursor"
    case "opencode": return "OpenCode"
    default: return id
    }
  }
}

/// A per-period point holds provider data without exposing transcript paths.
public struct UsageSeriesPoint: Sendable, Equatable, Codable, Identifiable {
  public let period: String
  public let provider: String
  public let processedTokens: Int64
  public let estimatedCostUSD: Double?
  public var id: String { "\(period)|\(provider)" }

  public init(period: String, provider: String, processedTokens: Int64, estimatedCostUSD: Double?) {
    self.period = period
    self.provider = provider
    self.processedTokens = processedTokens
    self.estimatedCostUSD = estimatedCostUSD
  }
}

/// Token categories and optional estimated costs use T3's bucket accounting.
public struct UsageCategories: Sendable, Equatable, Codable {
  public let input: Int64
  public let cacheRead: Int64
  public let cacheWrite: Int64
  public let output: Int64
  public let inputCost: Double?
  public let cacheReadCost: Double?
  public let cacheWriteCost: Double?
  public let outputCost: Double?
  public let cacheSavingsUSD: Double?

  public init(
    input: Int64, cacheRead: Int64, cacheWrite: Int64, output: Int64,
    inputCost: Double?, cacheReadCost: Double?, cacheWriteCost: Double?, outputCost: Double?,
    cacheSavingsUSD: Double?
  ) {
    self.input = input
    self.cacheRead = cacheRead
    self.cacheWrite = cacheWrite
    self.output = output
    self.inputCost = inputCost
    self.cacheReadCost = cacheReadCost
    self.cacheWriteCost = cacheWriteCost
    self.outputCost = outputCost
    self.cacheSavingsUSD = cacheSavingsUSD
  }
}
