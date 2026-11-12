import Foundation
import Network
import UsageCore

/// Serves a credential-free snapshot only on the IPv4 loopback interface.
final class LocalSnapshotServer: @unchecked Sendable {
  private let queue = DispatchQueue(label: "local.t3usagewidget.snapshot")
  private let lock = NSLock()
  private var snapshot = UsageSnapshot.disconnected
  private var language =
    UsageLanguage(rawValue: UserDefaults.standard.string(forKey: "usageLanguage") ?? "") ?? .system
  private var tab: UsageTab =
    UsageTab(rawValue: UserDefaults.standard.string(forKey: "usageTab") ?? "") ?? .cost
  private var listener: NWListener?
  var onTabChange: (@Sendable (UsageTab) -> Void)?
  var onPeriodChange: (@Sendable (UsagePeriod) -> Void)?
  var onReady: (@Sendable () -> Void)?
  var onFailure: (@Sendable () -> Void)?

  func start() throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(
      host: "127.0.0.1", port: NWEndpoint.Port(rawValue: LocalSnapshotClient.port)!)
    let listener = try NWListener(using: parameters)
    listener.stateUpdateHandler = { [weak self] state in
      switch state {
      case .ready: self?.onReady?()
      case .failed: self?.onFailure?()
      default: break
      }
    }
    listener.newConnectionHandler = { [weak self] connection in
      self?.handle(connection)
    }
    self.listener = listener
    listener.start(queue: queue)
  }

  func selectLanguage(_ value: UsageLanguage) {
    lock.lock()
    language = value
    lock.unlock()
    UserDefaults.standard.set(value.rawValue, forKey: "usageLanguage")
  }

  func selectTab(_ value: UsageTab) {
    lock.lock()
    tab = value
    lock.unlock()
    UserDefaults.standard.set(value.rawValue, forKey: "usageTab")
  }

  func update(_ value: UsageSnapshot) {
    lock.lock()
    snapshot = value
    lock.unlock()
  }

  private func handle(_ connection: NWConnection) {
    connection.start(queue: queue)
    receiveRequest(connection, accumulated: Data())
  }

  private func receiveRequest(_ connection: NWConnection, accumulated: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
      [weak self] data, _, complete, error in
      guard let self else {
        connection.cancel()
        return
      }
      var request = accumulated
      if let data { request.append(data) }
      guard request.count <= 4096, error == nil else {
        connection.cancel()
        return
      }
      guard request.suffix(4) == Data("\r\n\r\n".utf8) else {
        if complete {
          connection.cancel()
        } else {
          self.receiveRequest(connection, accumulated: request)
        }
        return
      }
      guard let route = LoopbackRequest.parse(request) else {
        self.send(connection, status: "404 Not Found", body: Data())
        return
      }
      self.lock.lock()
      switch route {
      case .usage:
        let current = self.snapshot.selecting(self.tab).withLanguage(self.language)
        self.lock.unlock()
        let body = (try? JSONEncoder().encode(current)) ?? Data()
        self.send(connection, status: "200 OK", body: body)
      case .selectTab(let tab):
        self.tab = tab
        self.lock.unlock()
        UserDefaults.standard.set(tab.rawValue, forKey: "usageTab")
        self.onTabChange?(tab)
        self.send(connection, status: "204 No Content", body: Data())
      case .selectPeriod(let period):
        self.lock.unlock()
        self.onPeriodChange?(period)
        self.send(connection, status: "204 No Content", body: Data())
      }
    }
  }

  private func send(_ connection: NWConnection, status: String, body: Data) {
    var response = Data(
      "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        .utf8)
    response.append(body)
    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
  }
}
