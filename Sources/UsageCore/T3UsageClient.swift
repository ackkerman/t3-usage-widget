import Foundation

/// Reads the local T3 server through a short-lived, read-only session.
public struct T3UsageClient: Sendable {
  public init() {}

  public func read(period: UsagePeriod = .month) async throws -> UsageSnapshot {
    let now = Date()
    let window = UsageWindow(period: period, now: now, timeZone: .current)
    let home = FileManager.default.homeDirectoryForCurrentUser
    let runtime = try JSONDecoder().decode(
      Runtime.self,
      from: Data(contentsOf: home.appendingPathComponent(".t3/userdata/server-runtime.json")))
    guard let base = URL(string: runtime.origin),
      base.host == "127.0.0.1" || base.host == "localhost", base.scheme == "http"
    else { throw ClientError.invalidOrigin }
    let token = try await issueToken()
    let local = try await readEnvironment(base: base, token: token, window: window, secure: false)
    guard let remote = try RemoteEnvironment.configured() else {
      return try UsageSummaryReducer.snapshot(
        local.usage, limits: local.limits, updatedAt: now, period: period)
    }
    do {
      try await remote.verifyIdentity()
      let other = try await readEnvironment(
        base: remote.baseURL, token: remote.token(), window: window, secure: true)
      let merged = try UsageEnvironmentMerger.merge([
        EnvironmentUsage(id: "local", summary: local.usage),
        EnvironmentUsage(id: remote.environmentID, summary: other.usage),
      ])
      return try UsageSummaryReducer.snapshot(
        merged.summary, limits: local.limits + other.limits, updatedAt: now, period: period
      ).includingRemote()
    } catch {
      let snapshot = try UsageSummaryReducer.snapshot(
        local.usage, limits: local.limits, updatedAt: now, period: period)
      return snapshot.withStatus(.partial)
    }
  }

  private func readEnvironment(base: URL, token: String, window: UsageWindow, secure: Bool)
    async throws -> (usage: UsageResponse, limits: [UsageLimit])
  {
    var ticketRequest = URLRequest(url: base.appendingPathComponent("api/auth/websocket-ticket"))
    ticketRequest.httpMethod = "POST"
    ticketRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (ticketData, ticketResponse) = try await RemoteEnvironment.session.data(for: ticketRequest)
    guard (ticketResponse as? HTTPURLResponse)?.statusCode == 200 else {
      throw ClientError.authentication
    }
    let ticket = try JSONDecoder().decode(Ticket.self, from: ticketData)
    var components = URLComponents(
      url: base.appendingPathComponent("ws"), resolvingAgainstBaseURL: false)!
    components.scheme = secure ? "wss" : "ws"
    components.queryItems = [
      URLQueryItem(name: "wsTicket", value: ticket.ticket),
      URLQueryItem(name: "orchestrationProtocol", value: "2"),
    ]
    guard let url = components.url else { throw ClientError.invalidOrigin }
    let socket = RemoteEnvironment.session.webSocketTask(with: url)
    socket.resume()
    let timeout = Task {
      try? await Task.sleep(for: .seconds(30))
      if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
    }
    defer {
      timeout.cancel()
      socket.cancel(with: .normalClosure, reason: nil)
    }
    let requests: [[String: Any]] = [
      [
        "_tag": "Request", "id": "usage", "tag": "server.getUsageSummary",
        "payload": window.payload, "headers": [],
      ],
      [
        "_tag": "Request", "id": "limits", "tag": "subscribeServerConfig",
        "payload": ["usageLimitsCommand": true], "headers": [],
      ],
    ]
    for request in requests {
      let data = try JSONSerialization.data(withJSONObject: request)
      try await socket.send(.data(data))
    }
    var usage: UsageResponse?
    var limits: [UsageLimit]?
    for _ in 0..<20 {
      let message = try await socket.receive()
      let data: Data
      switch message {
      case .data(let value): data = value
      case .string(let value): data = Data(value.utf8)
      @unknown default: continue
      }
      let decoded = try JSONDecoder().decode(Envelope.self, from: data)
      if decoded.requestId == "usage", decoded.exit?._tag == "Success" {
        usage = decoded.exit?.value
      }
      if decoded.requestId == "limits", let config = decoded.values?.first?.config {
        limits = config.providers.flatMap { provider in
          (provider.usageLimits?.windows ?? []).compactMap { window in
            UsageLimit(
              id: "\(provider.instanceId):\(window.id)",
              label: "\(provider.displayName) \(window.label)", usedPercent: window.usedPercent,
              resetsAt: window.resetsAt.flatMap(UsageDates.parse),
              resetCreditCount: window.kind == "weekly"
                ? provider.usageLimits?.resetCredits?.availableCount : nil,
              providerName: provider.displayName, windowName: window.label)
          }
        }
      }
      if let usage, let limits {
        return (usage, limits)
      }
    }
    throw ClientError.incomplete
  }

  private func issueToken() async throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "t3", "auth", "session", "issue", "--scope", "diagnostics:read", "--scope",
      "orchestration:read", "--ttl", "5m", "--label", "T3 Usage Widget", "--token-only",
    ]
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] =
      "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    process.environment = environment
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
      let token = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines), !token.isEmpty
    else { throw ClientError.authentication }
    return token
  }
}

public enum ClientError: LocalizedError, Equatable {
  case invalidOrigin, authentication, incomplete
  case unsupportedContract(Int)

  public var errorDescription: String? { message(language: .system) }

  public func message(language: UsageLanguage) -> String {
    switch self {
    case .invalidOrigin: return UsageStrings.text(.errorOrigin, language: language)
    case .authentication: return UsageStrings.text(.errorAuth, language: language)
    case .incomplete: return UsageStrings.text(.errorIncomplete, language: language)
    case .unsupportedContract(let version):
      return UsageStrings.text(.errorContract, language: language, String(version))
    }
  }

}
private struct Runtime: Decodable { let origin: String }
private struct Ticket: Decodable { let ticket: String }
private struct Envelope: Decodable {
  let requestId: String?
  let exit: Exit?
  let values: [ConfigEvent]?
}
private struct Exit: Decodable {
  let _tag: String
  let value: UsageResponse?
}
struct UsageResponse: Decodable {
  let contractVersion: Int
  let readAt: String?
  let sinceDay: String?
  let untilDay: String?
  let timeZone: String?
  let sinceTime: String?
  let untilTime: String?
  let modelFilter: UsageModelFilter?
  let buckets: [Bucket]
  let sources: [Source]
  let pricing: Pricing
}
struct UsageModelSelector: Decodable, Equatable {
  let provider: String?
  let model: String
}
struct UsageModelFilter: Decodable, Equatable {
  let include: [UsageModelSelector]?
  let exclude: [UsageModelSelector]?
}
struct Source: Decodable {
  let status: String
  let fingerprint: SourceFingerprint?
  let distinctSessions: Int?
}
struct SourceFingerprint: Decodable, Hashable {
  let hostId: String
  let provider: String
  let resolvedHomePath: String
  let volumeId: String
}
struct Pricing: Decodable { let status: String }
struct Bucket: Decodable {
  let day: String?
  let hourStart: String?
  let provider: String
  let model: String?
  let sourcePath: String?
  let totals: Totals
  let costUsd: Double
  let unpricedRecords: Int
  let categoryCostUsd: CategoryCosts?
  let cacheSavingsUsd: Double?
}
struct CategoryCosts: Decodable {
  let input: Double
  let cacheRead: Double
  let cacheWrite: Double
  let output: Double
}
struct Totals: Decodable {
  let uncachedInputTokens: Int64
  let cachedInputTokens: Int64
  let cacheCreationTokens: Int64
  let outputTokens: Int64
}
private struct ConfigEvent: Decodable { let config: Config? }
private struct Config: Decodable { let providers: [Provider] }
private struct Provider: Decodable {
  let instanceId: String
  let displayName: String
  let usageLimits: Limits?
}
private struct Limits: Decodable {
  let windows: [Window]
  let resetCredits: ResetCredits?
}
private struct ResetCredits: Decodable { let availableCount: Int }
private struct Window: Decodable {
  let id: String
  let label: String
  let kind: String?
  let usedPercent: Double
  let resetsAt: String?
}
