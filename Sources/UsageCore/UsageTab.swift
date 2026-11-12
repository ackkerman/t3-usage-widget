import Foundation

/// A tab selects one of T3's three usage views.
public enum UsageTab: String, CaseIterable, Sendable, Codable {
  case cost, tokens, limits
  public func label(language: UsageLanguage) -> String {
    let key: UsageStrings.Key
    switch self {
    case .cost: key = .tabCost
    case .tokens: key = .tabTokens
    case .limits: key = .tabLimits
    }
    return UsageStrings.text(key, language: language)
  }
}

extension UsageTab {
  /// Uses stable system symbols while accessibility names remain localized separately.
  public var systemImage: String {
    switch self {
    case .cost: return "dollarsign.circle"
    case .tokens: return "text.word.spacing"
    case .limits: return "gauge.with.dots.needle.67percent"
    }
  }
}
