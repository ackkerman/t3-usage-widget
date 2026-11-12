import Foundation

/// Routes only usage reads and presentation changes for the literal local endpoint.
public enum LoopbackRequest: Equatable {
  case usage
  case selectTab(UsageTab)
  case selectPeriod(UsagePeriod)

  public static func parse(_ data: Data) -> LoopbackRequest? {
    guard let text = String(data: data, encoding: .utf8), text.hasSuffix("\r\n\r\n") else {
      return nil
    }
    let lines = text.components(separatedBy: "\r\n")
    let hosts = lines.filter { $0.lowercased().hasPrefix("host:") }
    guard hosts.count == 1 else { return nil }
    let host = hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased()
    guard host == "127.0.0.1:\(LocalSnapshotClient.port)" else { return nil }
    if lines.first == "GET /usage HTTP/1.1" { return .usage }
    // Native widget intents do not send browser origin headers; reject browser-driven POSTs.
    let browserHeaders = ["origin:", "referer:", "sec-fetch-site:"]
    guard
      !lines.contains(where: { line in
        browserHeaders.contains { line.lowercased().hasPrefix($0) }
      })
    else { return nil }
    for tab in UsageTab.allCases {
      if lines.first == "POST /tab/\(tab.rawValue) HTTP/1.1" { return .selectTab(tab) }
    }
    for period in UsagePeriod.allCases {
      if lines.first == "POST /period/\(period.rawValue) HTTP/1.1" { return .selectPeriod(period) }
    }
    return nil
  }

  public static func isAllowed(_ data: Data) -> Bool { parse(data) == .usage }
}
