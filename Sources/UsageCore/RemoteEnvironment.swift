import Foundation
import Security

/// A user-authorized remote environment with its identity pinned before credentials are sent.
public struct RemoteEnvironment: Sendable {
  public let baseURL: URL
  public let environmentID: String
  private static let service = "local.t3usagewidget.remote"
  private static let account = "remote-session"

  public init(baseURL: URL, environmentID: String) throws {
    guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil,
      baseURL.user == nil, baseURL.password == nil, baseURL.query == nil,
      baseURL.fragment == nil, ["", "/", "/mcp", "/mcp/"].contains(baseURL.path),
      !environmentID.isEmpty
    else { throw ClientError.invalidOrigin }
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.path = ""
    self.baseURL = components.url!
    self.environmentID = environmentID
  }

  public static func configured() throws -> RemoteEnvironment? {
    let defaults = UserDefaults.standard
    guard let address = defaults.string(forKey: "remoteURL"),
      let url = URL(string: address), let id = defaults.string(forKey: "remoteEnvironmentID")
    else { return nil }
    return try RemoteEnvironment(baseURL: url, environmentID: id)
  }

  public func pair(code: String) async throws {
    try await verifyIdentity()
    var request = URLRequest(url: baseURL.appendingPathComponent("oauth/token"))
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var form = URLComponents()
    form.queryItems = [
      URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:token-exchange"),
      URLQueryItem(name: "subject_token", value: code),
      URLQueryItem(
        name: "subject_token_type", value: "urn:t3:params:oauth:token-type:environment-bootstrap"),
      URLQueryItem(
        name: "requested_token_type", value: "urn:ietf:params:oauth:token-type:access_token"),
      URLQueryItem(name: "scope", value: "diagnostics:read orchestration:read"),
      URLQueryItem(name: "client_label", value: "T3 Usage"),
    ]
    request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
    let (data, response) = try await Self.session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw ClientError.authentication
    }
    let token = try JSONDecoder().decode(AccessToken.self, from: data).accessToken
    guard !token.isEmpty else { throw ClientError.authentication }
    try Self.saveToken(token)
    UserDefaults.standard.set(baseURL.absoluteString, forKey: "remoteURL")
    UserDefaults.standard.set(environmentID, forKey: "remoteEnvironmentID")
  }

  public static func remove() throws {
    let result = SecItemDelete(keychainQuery as CFDictionary)
    guard result == errSecSuccess || result == errSecItemNotFound else {
      throw ClientError.authentication
    }
    UserDefaults.standard.removeObject(forKey: "remoteURL")
    UserDefaults.standard.removeObject(forKey: "remoteEnvironmentID")
  }

  func verifyIdentity() async throws {
    let url = baseURL.appendingPathComponent(".well-known/t3/environment")
    let (data, response) = try await Self.session.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      let descriptor = try? JSONDecoder().decode(Descriptor.self, from: data),
      descriptor.environmentId == environmentID
    else { throw ClientError.invalidOrigin }
  }

  func token() throws -> String {
    var query = Self.keychainQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data, let token = String(data: data, encoding: .utf8)
    else { throw ClientError.authentication }
    return token
  }

  private static var keychainQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
  private static func saveToken(_ token: String) throws {
    let data = Data(token.utf8)
    let status = SecItemUpdate(
      keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = keychainQuery
      item[kSecValueData as String] = data
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        throw ClientError.authentication
      }
    } else if status != errSecSuccess {
      throw ClientError.authentication
    }
  }
  static let session = URLSession(
    configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
  private struct Descriptor: Decodable { let environmentId: String }
  private struct AccessToken: Decodable {
    let accessToken: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
  }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
