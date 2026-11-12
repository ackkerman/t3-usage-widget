import Foundation

/// A period selects the same rolling-hour or calendar-day bounds as T3 Code.
public enum UsagePeriod: String, Codable, CaseIterable, Sendable, Identifiable {
  case day, week, month, quarter
  public var id: String { rawValue }
  public func label(language: UsageLanguage) -> String {
    let key: UsageStrings.Key
    switch self {
    case .day: key = .periodDay
    case .week: key = .periodWeek
    case .month: key = .periodMonth
    case .quarter: key = .periodQuarter
    }
    return UsageStrings.text(key, language: language)
  }
  public func shortLabel(language: UsageLanguage) -> String {
    let key: UsageStrings.Key
    switch self {
    case .day: key = .periodDayShort
    case .week: key = .periodWeekShort
    case .month: key = .periodMonthShort
    case .quarter: key = .periodQuarterShort
    }
    return UsageStrings.text(key, language: language)
  }
  var days: Int {
    switch self {
    case .day: return 1
    case .week: return 7
    case .month: return 30
    case .quarter: return 90
    }
  }
}

/// UTC timestamps define rolling hours; calendar dates use the requested local time zone.
public struct UsageWindow: Sendable, Equatable {
  public let sinceDay: String
  public let untilDay: String
  public let timeZone: String
  public let resolution: String
  public let sinceTime: String?
  public let untilTime: String?

  public init(period: UsagePeriod, now: Date, timeZone: TimeZone) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let dateFormat = DateFormatter()
    dateFormat.locale = Locale(identifier: "en_US_POSIX")
    dateFormat.calendar = calendar
    dateFormat.timeZone = timeZone
    dateFormat.dateFormat = "yyyy-MM-dd"
    self.timeZone = timeZone.identifier
    if period == .day {
      let end = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60)
      let start = end.addingTimeInterval(-24 * 60 * 60)
      let iso = ISO8601DateFormatter()
      iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      self.sinceDay = dateFormat.string(from: start)
      self.untilDay = dateFormat.string(from: end)
      self.resolution = "hour"
      self.sinceTime = iso.string(from: start)
      self.untilTime = iso.string(from: end)
    } else {
      let start = calendar.date(byAdding: .day, value: -(period.days - 1), to: now)!
      self.sinceDay = dateFormat.string(from: start)
      self.untilDay = dateFormat.string(from: now)
      self.resolution = "day"
      self.sinceTime = nil
      self.untilTime = nil
    }
  }

  var payload: [String: Any] {
    var result: [String: Any] = [
      "sinceDay": sinceDay, "untilDay": untilDay, "timeZone": timeZone,
      "resolution": resolution, "awaitRefresh": true,
    ]
    if let sinceTime { result["sinceTime"] = sinceTime }
    if let untilTime { result["untilTime"] = untilTime }
    return result
  }
}
