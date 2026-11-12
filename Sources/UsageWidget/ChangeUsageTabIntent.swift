import AppIntents
import UsageCore

/// Exposes only the widget's presentation selection, never credentials or data mutations.
struct ChangeUsageTabIntent: AppIntent {
  static let title: LocalizedStringResource = "intent_tab_title"
  static let description = IntentDescription("intent_tab_description")

  @Parameter(title: "intent_view") var tab: String

  init() { tab = UsageTab.cost.rawValue }
  init(_ selected: UsageTab) { tab = selected.rawValue }

  func perform() async throws -> some IntentResult {
    guard let selected = UsageTab(rawValue: tab) else { throw ClientError.incomplete }
    try await LocalSnapshotClient.select(selected)
    return .result()
  }
}

public struct T3UsageIntentsPackage: AppIntentsPackage {}

/// Changes the shared period through the host; data refresh remains owned by the app.
struct ChangeUsagePeriodIntent: AppIntent {
  static let title: LocalizedStringResource = "intent_period_title"
  static let description = IntentDescription("intent_period_description")
  @Parameter(title: "intent_period") var period: String

  init() { period = UsagePeriod.month.rawValue }
  init(_ selected: UsagePeriod) { period = selected.rawValue }

  func perform() async throws -> some IntentResult {
    guard let selected = UsagePeriod(rawValue: period) else { throw ClientError.incomplete }
    try await LocalSnapshotClient.selectPeriod(selected)
    return .result()
  }
}
