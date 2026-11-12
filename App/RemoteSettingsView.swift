import SwiftUI
import UsageCore

/// Connects an explicitly identified HTTPS environment using an independent session.
struct RemoteSettingsView: View {
  @Bindable var controller: UsageController
  @State private var address = ""
  @State private var identity = ""
  @State private var code = ""
  @State private var status = ""
  @State private var busy = false
  @State private var configured = (try? RemoteEnvironment.configured()) != nil

  private func label(_ ja: String, _ en: String, _ hans: String, _ hant: String) -> String {
    switch controller.language.resolved() {
    case .japanese: return ja
    case .simplifiedChinese: return hans
    case .traditionalChinese: return hant
    case .english, .system: return en
    }
  }

  var body: some View {
    DisclosureGroup(label("別環境", "Remote environment", "远程环境", "遠端環境")) {
      VStack(alignment: .leading, spacing: 8) {
        TextField("HTTPS URL", text: $address)
        TextField(label("環境 ID", "Environment ID", "环境 ID", "環境 ID"), text: $identity)
        SecureField(label("ペアリングコード", "Pairing code", "配对码", "配對碼"), text: $code)
        HStack {
          Button(label("接続", "Connect", "连接", "連線")) {
            Task { await connect() }
          }.disabled(busy || address.isEmpty || identity.isEmpty || code.isEmpty)
          if configured {
            Button(label("解除", "Disconnect", "断开", "中斷連線")) {
              do {
                try RemoteEnvironment.remove()
                configured = false
                status = label("接続を解除しました", "Disconnected", "已断开", "已中斷連線")
                Task { await controller.refresh() }
              } catch {
                status = label("解除できませんでした", "Could not disconnect", "无法断开", "無法中斷連線")
              }
            }.disabled(busy)
          }
        }
        if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
      }.padding(.top, 6)
    }
    .onAppear {
      if let remote = try? RemoteEnvironment.configured() {
        address = remote.baseURL.absoluteString
        identity = remote.environmentID
      }
    }
  }

  private func connect() async {
    busy = true
    defer {
      busy = false
      code = ""
    }
    do {
      guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        throw ClientError.invalidOrigin
      }
      let remote = try RemoteEnvironment(
        baseURL: url, environmentID: identity.trimmingCharacters(in: .whitespacesAndNewlines))
      try await remote.pair(code: code)
      configured = true
      status = label("接続しました", "Connected", "已连接", "已連線")
      await controller.refresh()
    } catch {
      status = label(
        "接続できませんでした。URL・環境 ID・コードを確認してください。",
        "Could not connect. Check the URL, environment ID, and code.",
        "无法连接。请检查 URL、环境 ID 和配对码。", "無法連線。請檢查 URL、環境 ID 和配對碼。")
    }
  }
}
