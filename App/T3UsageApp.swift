import SwiftUI
import UsageCore
import UsageWidget
import WidgetKit

@main struct T3UsageApp: App {
  init() {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.count == 5 && arguments[1] == "--pair-file" {
      let file = arguments[2]
      let address = arguments[3]
      let identity = arguments[4]
      Task.detached {
        do {
          guard let url = URL(string: address) else { throw ClientError.invalidOrigin }
          let code = try String(contentsOfFile: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
          try await RemoteEnvironment(baseURL: url, environmentID: identity).pair(code: code)
          print("Remote environment paired")
          exit(0)
        } catch {
          fputs("Remote environment pairing failed\n", stderr)
          exit(1)
        }
      }
      dispatchMain()
    }
  }
  @State private var controller = UsageController()

  var body: some Scene {
    WindowGroup {
      UsageHostView(controller: controller)
        .onAppear {
          configureApplicationIcon()
          controller.start()
        }
    }
    .windowResizability(.contentSize)

    MenuBarExtra {
      UsageMenuView(controller: controller)
    } label: {
      Label("T3 Usage", systemImage: "chart.xyaxis.line")
        .onAppear {
          configureApplicationIcon()
          controller.start()
        }
    }
    .menuBarExtraStyle(.window)
  }
}

private struct UsageHostView: View {
  @Bindable var controller: UsageController

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(UsageStrings.text(.appTitle, language: controller.language)).font(.title2.bold())
        Spacer()
        UsageLanguageMenu(controller: controller)
      }
      Text(UsageStrings.text(.appTagline, language: controller.language))
      UsagePeriodPicker(controller: controller)
      RemoteSettingsView(controller: controller)
      Text(controller.message).foregroundStyle(.secondary)
      Button {
        Task { await controller.refresh() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .help(UsageStrings.text(.refresh, language: controller.language))
      .accessibilityLabel(Text(UsageStrings.text(.refresh, language: controller.language)))
      .disabled(controller.isRefreshing || !controller.serverReady)
      Text(UsageStrings.text(.privacy, language: controller.language))
        .font(.caption).foregroundStyle(.secondary)
      Text(UsageStrings.text(.instructions, language: controller.language))
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(24).frame(width: 440)
    .environment(\.locale, controller.language.locale)
  }
}

private struct UsagePeriodPicker: View {
  @Bindable var controller: UsageController
  var body: some View {
    Picker(
      UsageStrings.text(.period, language: controller.language),
      selection: Binding(get: { controller.period }, set: { controller.setPeriod($0) })
    ) {
      ForEach(UsagePeriod.allCases) { period in
        Text(period.label(language: controller.language)).tag(period)
      }
    }
    .pickerStyle(.segmented)
    .disabled(controller.isRefreshing || !controller.serverReady)
  }
}

private struct UsageMenuView: View {
  @Bindable var controller: UsageController
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("T3 Usage").font(.headline)
        Spacer()
        Button {
          Task { await controller.refresh() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain).disabled(controller.isRefreshing || !controller.serverReady)
        .help(UsageStrings.text(.refresh, language: controller.language))
        .accessibilityLabel(Text(UsageStrings.text(.refresh, language: controller.language)))
      }
      UsagePeriodPicker(controller: controller)
      Picker(
        UsageStrings.text(.view, language: controller.language),
        selection: Binding(get: { controller.tab }, set: { controller.setTab($0) })
      ) {
        ForEach(UsageTab.allCases, id: \.rawValue) { tab in
          Image(systemName: tab.systemImage)
            .help(tab.label(language: controller.language))
            .accessibilityLabel(Text(tab.label(language: controller.language)))
            .tag(tab)
        }
      }.pickerStyle(.segmented)
      if controller.snapshot.status == .loading || controller.snapshot.status == .disconnected {
        Text(controller.message).font(.caption).foregroundStyle(.secondary)
        Spacer(minLength: 0)
      } else if controller.tab == .limits {
        UsageLimitView(snapshot: controller.snapshot, family: .systemLarge)
        Spacer(minLength: 0)
      } else {
        UsageMetricView(snapshot: controller.snapshot, metric: controller.tab, family: .systemLarge)
        Spacer(minLength: 0)
      }
      HStack {
        Text(
          controller.message
        ).font(.caption2).foregroundStyle(.secondary)
        Spacer()
        UsageLanguageMenu(controller: controller)
        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Image(systemName: "power")
        }
        .buttonStyle(.plain)
        .help(UsageStrings.text(.quit, language: controller.language))
        .accessibilityLabel(Text(UsageStrings.text(.quit, language: controller.language)))
      }
    }
    .padding(16).frame(width: 380, height: 390, alignment: .topLeading)
    .environment(\.locale, controller.language.locale)
  }
}

private struct UsageLanguageMenu: View {
  @Bindable var controller: UsageController
  var body: some View {
    Menu {
      ForEach(UsageLanguage.allCases) { language in
        Button {
          controller.setLanguage(language)
        } label: {
          if controller.language == language {
            Label(language.menuName(in: controller.language), systemImage: "checkmark")
          } else {
            Text(language.menuName(in: controller.language))
          }
        }
      }
    } label: {
      Image(systemName: "globe")
    }
    .help(UsageStrings.text(.language, language: controller.language))
    .accessibilityLabel(Text(UsageStrings.text(.language, language: controller.language)))
  }
}

private enum HostMessage {
  case connecting, changingPeriod, partial
  case updated(Date)
  case portError, serverError
  case error(ClientError)
}

@MainActor @Observable final class UsageController {
  private let server = LocalSnapshotServer()
  private var updateTask: Task<Void, Never>?
  private var messageState: HostMessage = .connecting
  var language =
    UsageLanguage(rawValue: UserDefaults.standard.string(forKey: "usageLanguage") ?? "") ?? .system
  var message: String {
    switch messageState {
    case .connecting: return UsageStrings.text(.connecting, language: language)
    case .changingPeriod: return UsageStrings.text(.changingPeriod, language: language)
    case .partial: return UsageStrings.text(.partialMessage, language: language)
    case .portError: return UsageStrings.text(.portError, language: language)
    case .serverError: return UsageStrings.text(.serverError, language: language)
    case .error(let error):
      return UsageStrings.text(.updateError, language: language, error.message(language: language))
    case .updated(let date):
      let formatter = DateFormatter()
      formatter.locale = language.locale
      formatter.dateStyle = .none
      formatter.timeStyle = .short
      return UsageStrings.text(.updated, language: language, formatter.string(from: date))
    }
  }
  var isRefreshing = false
  var serverReady = false
  var snapshot = UsageSnapshot.disconnected
  var tab = UsageTab(rawValue: UserDefaults.standard.string(forKey: "usageTab") ?? "") ?? .cost
  var period =
    UsagePeriod(rawValue: UserDefaults.standard.string(forKey: "usagePeriod") ?? "") ?? .month

  func start() {
    guard updateTask == nil else { return }
    updateTask = Task { await run() }
  }

  func setLanguage(_ value: UsageLanguage) {
    guard value != language else { return }
    language = value
    snapshot = snapshot.withLanguage(value)
    server.selectLanguage(value)
    WidgetCenter.shared.reloadAllTimelines()
  }

  func setPeriod(_ value: UsagePeriod) {
    guard value != period else { return }
    period = value
    UserDefaults.standard.set(period.rawValue, forKey: "usagePeriod")
    snapshot = .loading(period: period, tab: tab).withLanguage(language)
    server.update(snapshot)
    WidgetCenter.shared.reloadAllTimelines()
    messageState = .changingPeriod
    Task { await refresh() }
  }

  func setTab(_ value: UsageTab) {
    guard value != tab else { return }
    tab = value
    server.selectTab(value)
    WidgetCenter.shared.reloadAllTimelines()
  }

  private func run() async {
    do {
      server.onTabChange = { [weak self] tab in Task { @MainActor in self?.tab = tab } }
      server.onPeriodChange = { [weak self] period in Task { @MainActor in self?.setPeriod(period) }
      }
      server.onReady = { [weak self] in
        Task { @MainActor in
          guard let self else { return }
          self.serverReady = true
          await self.refresh()
        }
      }
      server.onFailure = { [weak self] in
        Task { @MainActor in
          guard let self else { return }
          self.serverReady = false
          self.snapshot = .disconnected.withLanguage(self.language)
          self.server.update(.disconnected)
          self.messageState = .portError
          WidgetCenter.shared.reloadAllTimelines()
        }
      }
      try server.start()
    } catch {
      messageState = .serverError
      return
    }
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(900))
      if !Task.isCancelled { await refresh() }
    }
  }

  func refresh() async {
    guard serverReady, !isRefreshing else { return }
    isRefreshing = true
    let requestedPeriod = period
    defer {
      isRefreshing = false
      if serverReady && period != requestedPeriod { Task { await refresh() } }
    }
    do {
      let result = try await T3UsageClient().read(period: requestedPeriod)
      guard serverReady, period == requestedPeriod else { return }
      snapshot = result.withLanguage(language)
      server.update(snapshot)
      WidgetCenter.shared.reloadAllTimelines()
      messageState = result.status == .partial ? .partial : .updated(.now)
    } catch {
      guard serverReady, period == requestedPeriod else { return }
      snapshot = .disconnected.withLanguage(language)
      server.update(snapshot)
      WidgetCenter.shared.reloadAllTimelines()
      messageState = .error(error as? ClientError ?? .incomplete)
    }
  }
}

@MainActor private func configureApplicationIcon() {
  guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
    let icon = NSImage(contentsOf: url)
  else { return }
  NSApplication.shared.applicationIconImage = icon
}
