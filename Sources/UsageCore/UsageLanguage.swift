import Foundation

/// A persisted language choice. System follows the first supported preferred language.
public enum UsageLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
  case system, japanese, english, simplifiedChinese, traditionalChinese
  public var id: String { rawValue }

  public func menuName(in current: UsageLanguage) -> String {
    switch self {
    case .system: return UsageStrings.text(.system, language: current)
    case .japanese: return "日本語"
    case .english: return "English"
    case .simplifiedChinese: return "简体中文"
    case .traditionalChinese: return "繁體中文"
    }
  }

  public func resolved(preferred: [String] = Locale.preferredLanguages) -> UsageLanguage {
    guard self == .system else { return self }
    for item in preferred {
      let value = item.replacingOccurrences(of: "_", with: "-").lowercased()
      if value == "ja" || value.hasPrefix("ja-") { return .japanese }
      if value == "en" || value.hasPrefix("en-") { return .english }
      if value == "zh" || value.hasPrefix("zh-") {
        if value.contains("hant") || value.hasPrefix("zh-tw") || value.hasPrefix("zh-hk")
          || value.hasPrefix("zh-mo")
        {
          return .traditionalChinese
        }
        return .simplifiedChinese
      }
    }
    return .english
  }

  public var locale: Locale {
    switch resolved() {
    case .japanese: return Locale(identifier: "ja_JP")
    case .simplifiedChinese: return Locale(identifier: "zh_Hans_CN")
    case .traditionalChinese: return Locale(identifier: "zh_Hant_TW")
    case .english, .system: return Locale(identifier: "en_US")
    }
  }

  fileprivate var resourceName: String {
    switch self {
    case .japanese: return "ja"
    case .simplifiedChinese: return "zh-Hans"
    case .traditionalChinese: return "zh-Hant"
    case .english, .system: return "en"
    }
  }
}

/// Uses a selected language without changing the system or another app's locale.
public enum UsageStrings {
  public enum Key: String, CaseIterable, Sendable {
    case language
    case system
    case periodDay = "period_day"
    case periodWeek = "period_week"
    case periodMonth = "period_month"
    case periodQuarter = "period_quarter"
    case periodDayShort = "period_day_short"
    case periodWeekShort = "period_week_short"
    case periodMonthShort = "period_month_short"
    case periodQuarterShort = "period_quarter_short"
    case tabCost = "tab_cost"
    case tabTokens = "tab_tokens"
    case tabLimits = "tab_limits"
    case appTitle = "app_title"
    case appTagline = "app_tagline"
    case period
    case view
    case refresh
    case privacy
    case instructions
    case connecting
    case changingPeriod = "changing_period"
    case partialMessage = "partial_message"
    case updated
    case portError = "port_error"
    case updateError = "update_error"
    case serverError = "server_error"
    case errorOrigin = "error_origin"
    case errorAuth = "error_auth"
    case errorIncomplete = "error_incomplete"
    case errorContract = "error_contract"
    case unpricedExcluded = "unpriced_excluded"
    case thisMac = "this_mac"
    case connectedEnvironments = "connected_environments"
    case quit
    case loading
    case loadingAccessibility = "loading_accessibility"
    case disconnected
    case openApp = "open_app"
    case sample
    case partialShort = "partial_short"
    case noData = "no_data"
    case chartTokens = "chart_tokens"
    case chartCost = "chart_cost"
    case dailyTokens = "daily_tokens"
    case dailyCost = "daily_cost"
    case tokensUnit = "tokens_unit"
    case apiEstimate = "api_estimate"
    case sessions
    case moreCount = "more_count"
    case cachedValue = "cached_value"
    case inputValue = "input_value"
    case outputValue = "output_value"
    case cacheSavings = "cache_savings"
    case tokensByType = "tokens_by_type"
    case costByType = "cost_by_type"
    case input
    case cacheRead = "cache_read"
    case cacheWrite = "cache_write"
    case output
    case breakdownUnavailable = "breakdown_unavailable"
    case limitsUnavailable = "limits_unavailable"
    case remaining
    case remainingAccessibility = "remaining_accessibility"
    case reset
    case resetCredits = "reset_credits"
    case show
    case weekly
    case session
    case monthly
    case hourlyTokens = "hourly_tokens"
    case hourlyCost = "hourly_cost"
    case chartDate = "chart_date"
    case chartValue = "chart_value"
    case chartProvider = "chart_provider"
    case widgetDescription = "widget_description"
  }

  public static func text(
    _ key: Key, language: UsageLanguage, preferred: [String] = Locale.preferredLanguages,
    _ args: CVarArg...
  ) -> String {
    let selected = language.resolved(preferred: preferred)
    let name = selected.resourceName
    let bundle =
      Bundle.module.path(forResource: name, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
    let format = bundle.localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
    guard !args.isEmpty else { return format }
    return String(format: format, locale: selected.locale, arguments: args)
  }
}
