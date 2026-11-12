import Foundation

/// A complete chart point includes empty intervals so gaps render as zero instead of interpolating across them.
public struct UsageChartSample: Sendable, Equatable, Identifiable {
  public let date: Date
  public let provider: String
  public let tokens: Int64
  public let costUSD: Double?
  public let costSegment: Int
  public var id: String { "\(date.timeIntervalSince1970)|\(provider)" }
}

public enum UsageChartData {
  public static func samples(_ snapshot: UsageSnapshot, timeZone: TimeZone = .current)
    -> [UsageChartSample]
  {
    guard let updatedAt = snapshot.updatedAt, !snapshot.providers.isEmpty else { return [] }
    let window = UsageWindow(period: snapshot.period, now: updatedAt, timeZone: timeZone)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let dayFormat = DateFormatter()
    dayFormat.locale = Locale(identifier: "en_US_POSIX")
    dayFormat.calendar = calendar
    dayFormat.timeZone = timeZone
    dayFormat.dateFormat = "yyyy-MM-dd"
    let start: Date
    let end: Date
    if snapshot.period == .day {
      guard let from = window.sinceTime.flatMap(UsageDates.parse),
        let until = window.untilTime.flatMap(UsageDates.parse)
      else { return [] }
      start = from
      end = until
    } else {
      guard let from = dayFormat.date(from: window.sinceDay),
        let untilDay = dayFormat.date(from: window.untilDay),
        let until = calendar.date(byAdding: .day, value: 1, to: untilDay)
      else { return [] }
      start = from
      end = until
    }
    var indexed: [String: UsageSeriesPoint] = [:]
    for point in snapshot.series {
      let date =
        snapshot.period == .day
        ? UsageDates.parse(point.period) : dayFormat.date(from: point.period)
      guard let date else { continue }
      indexed["\(date.timeIntervalSince1970)|\(point.provider)"] = point
    }
    var result: [UsageChartSample] = []
    var costSegments: [String: Int] = [:]
    var cursor = start
    while cursor < end && result.count < 10_000 {
      for provider in snapshot.providers {
        let point = indexed["\(cursor.timeIntervalSince1970)|\(provider.id)"]
        let cost = point == nil ? 0 : point?.estimatedCostUSD
        let segment = costSegments[provider.id, default: 0]
        result.append(
          UsageChartSample(
            date: cursor, provider: provider.id,
            tokens: point?.processedTokens ?? 0, costUSD: cost, costSegment: segment))
        if cost == nil { costSegments[provider.id] = segment + 1 }

      }
      if snapshot.period == .day {
        cursor = cursor.addingTimeInterval(3600)
      } else if let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor {
        cursor = next
      } else {
        break
      }
    }
    return result
  }
}
