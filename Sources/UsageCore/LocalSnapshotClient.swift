import Foundation

/// Reads only the host's loopback snapshot; credentials never cross this interface.
public enum LocalSnapshotClient {
  public static let port: UInt16 = 47831
  public static let maxAge: TimeInterval = 30 * 60

  public static func cachedLanguage() -> UsageLanguage {
    UsageLanguage(rawValue: UserDefaults.standard.string(forKey: "usageWidgetLanguage") ?? "")
      ?? .system
  }

  public static func read(timeout: TimeInterval = 5) async -> UsageSnapshot {
    let saved = cachedLanguage()
    let unavailable = UsageSnapshot.disconnected.withLanguage(saved)
    guard let url = URL(string: "http://127.0.0.1:\(port)/usage") else { return unavailable }
    var request = URLRequest(url: url)
    request.timeoutInterval = timeout
    request.cachePolicy = .reloadIgnoringLocalCacheData
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200,
        data.count < 1_048_576,
        let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
      else { return unavailable }
      UserDefaults.standard.set(snapshot.language.rawValue, forKey: "usageWidgetLanguage")
      return current(snapshot, now: .now)
    } catch {
      return unavailable
    }
  }

  /// Requests a presentation-only tab change from the local host.
  public static func select(_ tab: UsageTab) async throws {
    guard let url = URL(string: "http://127.0.0.1:\(port)/tab/\(tab.rawValue)") else {
      throw ClientError.invalidOrigin
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 5
    let (_, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 204 else { throw ClientError.incomplete }
  }

  /// Requests a bounded period change from the host.
  public static func selectPeriod(_ period: UsagePeriod) async throws {
    guard let url = URL(string: "http://127.0.0.1:\(port)/period/\(period.rawValue)") else {
      throw ClientError.invalidOrigin
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 5
    let (_, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 204 else { throw ClientError.incomplete }
  }

  /// Schedules a disconnected entry so a delayed refresh does not leave a value indefinitely current.
  public static func expiration(of snapshot: UsageSnapshot, now: Date) -> Date? {
    guard current(snapshot, now: now).status != .disconnected, let updatedAt = snapshot.updatedAt
    else { return nil }
    let deadline = updatedAt.addingTimeInterval(maxAge)
    return deadline > now ? deadline : nil
  }

  /// An expired or implausibly future timestamp cannot establish current usage.
  public static func current(_ snapshot: UsageSnapshot, now: Date) -> UsageSnapshot {
    guard let updatedAt = snapshot.updatedAt,
      updatedAt <= now.addingTimeInterval(60),
      now.timeIntervalSince(updatedAt) < maxAge
    else { return .disconnected.selecting(snapshot.tab).withLanguage(snapshot.language) }
    return snapshot
  }
}
