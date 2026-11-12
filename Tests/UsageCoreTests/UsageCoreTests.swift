import Foundation
import Testing

@testable import UsageCore

@Test func unavailableValuesAreNotZero() {
  #expect(UsageFormatting.tokens(nil) == "—")
  #expect(UsageFormatting.cost(nil) == "—")
  #expect(UsageFormatting.tokens(0) == "0")
  #expect(UsageFormatting.cost(0) == "$0.00")
  #expect(UsageSnapshot.disconnected.status == .disconnected)
}

@Test func usageValuesHaveReadableFormatting() {
  #expect(UsageFormatting.tokens(23_900_000_000) == "23.9B")
  #expect(UsageFormatting.tokens(122_000_000) == "122.0M")
  #expect(UsageFormatting.cost(1372.73) == "$1,372.73")
}

@Test func invalidLimitsAndCostsAreRejected() {
  #expect(UsageLimit(id: "weekly", label: "Weekly", usedPercent: 101) == nil)
  #expect(UsageLimit(id: "", label: "Weekly", usedPercent: 50) == nil)
  #expect(UsageLimit(id: "weekly", label: "Weekly", usedPercent: 50)?.usedPercent == 50)
  #expect(UsageFormatting.cost(.nan) == "—")
  #expect(UsageFormatting.tokens(-1) == "—")
}

@Test func snapshotRoundTripsWithoutCredentials() throws {
  let snapshot = UsageSnapshot(
    processedTokens: 42, estimatedCostUSD: nil,
    limits: [UsageLimit(id: "p:weekly", label: "Weekly", usedPercent: 20)!],
    updatedAt: Date(timeIntervalSince1970: 0), status: .partial, period: .week)
  let data = try JSONEncoder().encode(snapshot)
  #expect(try JSONDecoder().decode(UsageSnapshot.self, from: data) == snapshot)
  #expect(!String(decoding: data, as: UTF8.self).contains("token"))
}

@Test func staleAndFutureSnapshotsAreNotDisplayedAsCurrent() {
  let now = Date(timeIntervalSince1970: 10_000)
  func snapshot(_ date: Date) -> UsageSnapshot {
    UsageSnapshot(
      processedTokens: 7, estimatedCostUSD: 0, limits: [], updatedAt: date, status: .connected)
  }
  #expect(LocalSnapshotClient.current(snapshot(now), now: now).processedTokens == 7)
  #expect(
    LocalSnapshotClient.current(snapshot(now.addingTimeInterval(-1801)), now: now) == .disconnected)
  #expect(
    LocalSnapshotClient.current(snapshot(now.addingTimeInterval(61)), now: now) == .disconnected)
}

@Test func loopbackEndpointRejectsOtherHostsAndMethods() {
  func request(_ text: String) -> Data { Data(text.utf8) }
  #expect(
    LoopbackRequest.isAllowed(request("GET /usage HTTP/1.1\r\nHost: 127.0.0.1:47831\r\n\r\n")))
  #expect(
    !LoopbackRequest.isAllowed(request("GET /usage HTTP/1.1\r\nHost: evil.example:47831\r\n\r\n")))
  #expect(
    !LoopbackRequest.isAllowed(request("POST /usage HTTP/1.1\r\nHost: 127.0.0.1:47831\r\n\r\n")))
  #expect(
    !LoopbackRequest.isAllowed(
      request("GET /usage HTTP/1.1\r\nHost: 127.0.0.1:47831\r\nHost: evil.example\r\n\r\n")))
  #expect(!LoopbackRequest.isAllowed(request("GET /usage HTTP/1.1\r\nHost: 127.0.0.1:47831\r\n")))
}

@Test func summaryDistinguishesMissingSourcesFromAnEmptyPeriod() throws {
  func summary(_ source: String) throws -> UsageResponse {
    let json = """
      {"contractVersion":6,"buckets":[],"sources":[{"status":"\(source)"}],"pricing":{"status":"cached"}}
      """
    return try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
  }
  let missing = try UsageSummaryReducer.snapshot(
    try summary("missing"), limits: [], updatedAt: .now)
  #expect(missing.processedTokens == nil)
  #expect(missing.estimatedCostUSD == nil)
  #expect(missing.status == .partial)
  let empty = try UsageSummaryReducer.snapshot(try summary("ok"), limits: [], updatedAt: .now)
  #expect(empty.processedTokens == 0)
  #expect(empty.estimatedCostUSD == 0)
  #expect(empty.status == .connected)
}

@Test func unknownPricesAreNotPresentedAsFinalCost() throws {
  let json = """
    {"contractVersion":6,"buckets":[{"provider":"codex","totals":{"uncachedInputTokens":10,"cachedInputTokens":20,"cacheCreationTokens":3,"outputTokens":4},"costUsd":0.2,"unpricedRecords":1}],"sources":[{"status":"ok"}],"pricing":{"status":"cached"}}
    """
  let usage = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
  let result = try UsageSummaryReducer.snapshot(usage, limits: [], updatedAt: .now)
  #expect(result.processedTokens == 37)
  #expect(result.estimatedCostUSD == 0.2)
  #expect(result.hasUnpricedUsage)
  #expect(result.status == .partial)
}

@Test func timelineExpiresAtTheSnapshotDeadline() {
  let now = Date(timeIntervalSince1970: 10_000)
  let snapshot = UsageSnapshot(
    processedTokens: 7, estimatedCostUSD: 1, limits: [], updatedAt: now, status: .connected)
  let deadline = now.addingTimeInterval(LocalSnapshotClient.maxAge)
  #expect(LocalSnapshotClient.expiration(of: snapshot, now: now) == deadline)
  #expect(LocalSnapshotClient.current(snapshot, now: deadline) == .disconnected)
  #expect(LocalSnapshotClient.expiration(of: snapshot, now: deadline) == nil)
  #expect(LocalSnapshotClient.expiration(of: .disconnected, now: now) == nil)
}

@Test func incompatibleUsageContractsCannotProduceSnapshots() throws {
  func usage(_ version: Int) throws -> UsageResponse {
    let json = """
      {"contractVersion":\(version),"buckets":[],"sources":[{"status":"ok"}],"pricing":{"status":"cached"}}
      """
    return try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
  }
  for version in [4, 5, 6] {
    let snapshot = try UsageSummaryReducer.snapshot(usage(version), limits: [], updatedAt: .now)
    #expect(snapshot.processedTokens == 0)
  }
  for version in [3, 7] {
    #expect(throws: ClientError.unsupportedContract(version)) {
      try UsageSummaryReducer.snapshot(usage(version), limits: [], updatedAt: .now)
    }
  }
}

@Test func incompatibleContractProvidesAnActionableMessage() {
  #expect(ClientError.unsupportedContract(7).message(language: .japanese).contains("バージョン 7"))
}

@Test func usageWindowsMatchCalendarDaysAcrossDaylightSaving() throws {
  let now = try #require(ISO8601DateFormatter().date(from: "2026-03-09T16:37:45Z"))
  let zone = try #require(TimeZone(identifier: "America/New_York"))
  let day = UsageWindow(period: .day, now: now, timeZone: zone)
  #expect(day.sinceTime == "2026-03-08T16:37:00.000Z")
  #expect(day.untilTime == "2026-03-09T16:37:00.000Z")
  #expect(day.sinceDay == "2026-03-08")
  #expect(day.untilDay == "2026-03-09")
  #expect(day.resolution == "hour")
  for (period, start) in [
    (UsagePeriod.week, "2026-03-03"), (.month, "2026-02-08"), (.quarter, "2025-12-10"),
  ] {
    let window = UsageWindow(period: period, now: now, timeZone: zone)
    #expect(window.sinceDay == start)
    #expect(window.untilDay == "2026-03-09")
    #expect(window.resolution == "day")
    #expect(window.sinceTime == nil)
    #expect(window.untilTime == nil)
  }
}

@Test func providerBreakdownShowsKnownCostAndMarksUnpricedUsage() throws {
  let json = """
    {"contractVersion":6,"buckets":[
      {"provider":"codex","totals":{"uncachedInputTokens":10,"cachedInputTokens":20,"cacheCreationTokens":0,"outputTokens":5},"costUsd":1.2,"unpricedRecords":0},
      {"provider":"codex","totals":{"uncachedInputTokens":3,"cachedInputTokens":0,"cacheCreationTokens":2,"outputTokens":0},"costUsd":0.3,"unpricedRecords":0},
      {"provider":"claude","totals":{"uncachedInputTokens":9,"cachedInputTokens":0,"cacheCreationTokens":0,"outputTokens":1},"costUsd":0.4,"unpricedRecords":1}
    ],"sources":[{"status":"ok"}],"pricing":{"status":"cached"}}
    """
  let usage = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
  let result = try UsageSummaryReducer.snapshot(usage, limits: [], updatedAt: .now)
  #expect(result.providers.count == 2)
  #expect(result.providers[0].id == "codex")
  #expect(result.providers[0].processedTokens == 40)
  #expect(result.providers[0].estimatedCostUSD == 1.5)
  #expect(result.providers[1].id == "claude")
  #expect(result.providers[1].processedTokens == 10)
  #expect(result.providers[1].estimatedCostUSD == 0.4)
  #expect(result.estimatedCostUSD == 1.9)
  #expect(result.hasUnpricedUsage)
}

@Test func chartAndCategoriesPreserveBucketsAndDoNotExposeSourcePaths() throws {
  let json = """
    {"contractVersion":6,"buckets":[
      {"day":"2026-11-11","provider":"codex","totals":{"uncachedInputTokens":10,"cachedInputTokens":20,"cacheCreationTokens":2,"outputTokens":5},"costUsd":1.0,"cacheSavingsUsd":9.0,"categoryCostUsd":{"input":0.1,"cacheRead":0.2,"cacheWrite":0.3,"output":0.4},"unpricedRecords":0},
      {"day":"2026-11-11","provider":"codex","totals":{"uncachedInputTokens":3,"cachedInputTokens":0,"cacheCreationTokens":0,"outputTokens":2},"costUsd":0.5,"cacheSavingsUsd":1.0,"categoryCostUsd":{"input":0.1,"cacheRead":0.1,"cacheWrite":0.1,"output":0.2},"unpricedRecords":0},
      {"day":"2026-11-12","provider":"claude","totals":{"uncachedInputTokens":9,"cachedInputTokens":0,"cacheCreationTokens":0,"outputTokens":1},"costUsd":0.4,"cacheSavingsUsd":0,"unpricedRecords":1}
    ],"sources":[{"status":"ok","fingerprint":{"hostId":"host","provider":"codex","resolvedHomePath":"/private/secret/path","volumeId":"1"},"distinctSessions":2}],"pricing":{"status":"cached"}}
    """
  let usage = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
  let snapshot = try UsageSummaryReducer.snapshot(usage, limits: [], updatedAt: .now)
  #expect(snapshot.series.count == 2)
  #expect(snapshot.series[0].period == "2026-11-11")
  #expect(snapshot.series[0].processedTokens == 42)
  #expect(snapshot.series[0].estimatedCostUSD == 1.5)
  #expect(snapshot.series[1].estimatedCostUSD == nil)
  #expect(snapshot.providers.first?.sessions == 2)
  #expect(snapshot.categories?.input == 22)
  #expect(snapshot.categories?.cacheRead == 20)
  #expect(snapshot.categories?.cacheSavingsUSD == 10)
  #expect(snapshot.categories?.inputCost == nil)
  let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
  #expect(!encoded.contains("/private/secret/path"))
}

@Test func resetTimesSupportFractionalAndWholeSeconds() {
  #expect(UsageDates.parse("2026-11-18T08:40:04.000Z") != nil)
  #expect(UsageDates.parse("2026-11-18T08:40:04Z") != nil)
  #expect(UsageDates.parse("invalid") == nil)
}

@Test func tabChangesAreLimitedToKnownLocalRoutes() {
  func request(_ text: String) -> Data { Data(text.utf8) }
  #expect(
    LoopbackRequest.parse(request("POST /tab/tokens HTTP/1.1\r\nHost: 127.0.0.1:47831\r\n\r\n"))
      == .selectTab(.tokens))
  #expect(
    LoopbackRequest.parse(request("POST /tab/unknown HTTP/1.1\r\nHost: 127.0.0.1:47831\r\n\r\n"))
      == nil)
  #expect(
    LoopbackRequest.parse(request("POST /tab/cost HTTP/1.1\r\nHost: evil.example\r\n\r\n")) == nil)
  let snapshot = UsageSnapshot(
    processedTokens: 1, estimatedCostUSD: 2, limits: [], updatedAt: .now, status: .connected)
  #expect(snapshot.selecting(.limits).tab == .limits)
  #expect(snapshot.selecting(.limits).processedTokens == 1)
}

@Test func chartFillsMissingDaysButKeepsUnknownCostsUnknown() throws {
  let iso = ISO8601DateFormatter()
  let now = try #require(iso.date(from: "2026-03-09T16:37:00Z"))
  let snapshot = UsageSnapshot(
    processedTokens: 12, estimatedCostUSD: nil, limits: [], updatedAt: now,
    status: .partial, period: .week,
    providers: [UsageProviderSummary(id: "codex", processedTokens: 12, estimatedCostUSD: nil)],
    series: [
      UsageSeriesPoint(
        period: "2026-03-08", provider: "codex", processedTokens: 12, estimatedCostUSD: nil)
    ])
  let points = UsageChartData.samples(
    snapshot, timeZone: try #require(TimeZone(identifier: "America/New_York")))
  #expect(points.count == 7)
  #expect(points.filter { $0.tokens == 12 }.count == 1)
  #expect(points.filter { $0.costUSD == nil }.count == 1)
  #expect(points.filter { $0.costUSD == 0 }.count == 6)
  let unknownIndex = try #require(points.firstIndex(where: { $0.costUSD == nil }))
  #expect(points[unknownIndex - 1].costSegment == 0)
  #expect(points[unknownIndex + 1].costSegment == 1)
}

@Test func browserOriginCannotChangeWidgetSelection() {
  let request = Data(
    "POST /tab/tokens HTTP/1.1\r\nHost: 127.0.0.1:47831\r\nOrigin: https://example.com\r\n\r\n".utf8
  )
  #expect(LoopbackRequest.parse(request) == nil)
}

@Test func periodChangesAreLimitedToKnownLocalRoutes() {
  func request(_ text: String) -> Data { Data(text.utf8) }
  #expect(
    LoopbackRequest.parse(request("POST /period/week HTTP/1.1\r\nHost: 127.0.0.1:47831\r\n\r\n"))
      == .selectPeriod(.week))
  #expect(
    LoopbackRequest.parse(request("POST /period/invalid HTTP/1.1\r\nHost: 127.0.0.1:47831\r\n\r\n"))
      == nil)
  #expect(
    LoopbackRequest.parse(request("POST /period/week HTTP/1.1\r\nHost: evil.example\r\n\r\n"))
      == nil)
}

@Test func multipleEnvironmentsDeduplicateSourcesAndSupplementNewCells() throws {
  let old = """
    {"contractVersion":6,"readAt":"2026-11-11T10:00:00Z","sinceDay":"2026-11-10","untilDay":"2026-11-12","timeZone":"Asia/Tokyo",
     "buckets":[{"day":"2026-11-10","provider":"codex","model":"m","sourcePath":"/private/shared","totals":{"uncachedInputTokens":10,"cachedInputTokens":0,"cacheCreationTokens":0,"outputTokens":0},"costUsd":1,"unpricedRecords":0}],
     "sources":[{"status":"ok","fingerprint":{"hostId":"h","provider":"codex","resolvedHomePath":"/private/shared","volumeId":"v"},"distinctSessions":2}],"pricing":{"status":"cached"}}
    """
  let newer = """
    {"contractVersion":6,"readAt":"2026-11-12T10:00:00Z","sinceDay":"2026-11-10","untilDay":"2026-11-12","timeZone":"Asia/Tokyo",
     "buckets":[
      {"day":"2026-11-10","provider":"codex","model":"m","sourcePath":"/private/shared","totals":{"uncachedInputTokens":999,"cachedInputTokens":0,"cacheCreationTokens":0,"outputTokens":0},"costUsd":9,"unpricedRecords":0},
      {"day":"2026-11-11","provider":"codex","model":"m","sourcePath":"/private/shared","totals":{"uncachedInputTokens":5,"cachedInputTokens":0,"cacheCreationTokens":0,"outputTokens":0},"costUsd":0.5,"unpricedRecords":0},
      {"day":"2026-11-12","provider":"claude","model":"c","sourcePath":"/private/claude","totals":{"uncachedInputTokens":7,"cachedInputTokens":0,"cacheCreationTokens":0,"outputTokens":0},"costUsd":0.7,"unpricedRecords":0}],
     "sources":[{"status":"partial","fingerprint":{"hostId":"h","provider":"codex","resolvedHomePath":"/private/shared","volumeId":"v"},"distinctSessions":3},
      {"status":"ok","fingerprint":{"hostId":"h2","provider":"claude","resolvedHomePath":"/private/claude","volumeId":"v2"},"distinctSessions":1}],"pricing":{"status":"cached"}}
    """
  let decoder = JSONDecoder()
  let a = EnvironmentUsage(
    id: "a", summary: try decoder.decode(UsageResponse.self, from: Data(old.utf8)))
  let b = EnvironmentUsage(
    id: "b", summary: try decoder.decode(UsageResponse.self, from: Data(newer.utf8)))
  let merged = try UsageEnvironmentMerger.merge([a, b])
  #expect(merged.duplicateSourceCount == 1)
  #expect(merged.supplementedPartialSource)
  let snapshot = try UsageSummaryReducer.snapshot(merged.summary, limits: [], updatedAt: .now)
  #expect(snapshot.processedTokens == 22)
  #expect(snapshot.providers.first(where: { $0.id == "codex" })?.sessions == 3)
  #expect(snapshot.providers.first(where: { $0.id == "claude" })?.processedTokens == 7)
  let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
  #expect(!encoded.contains("/private/"))
}

@Test func multipleEnvironmentsRejectDifferentPeriodsAndDuplicateIDs() throws {
  func summary(_ until: String) throws -> UsageResponse {
    let json = """
      {"contractVersion":6,"readAt":"2026-11-12T10:00:00Z","sinceDay":"2026-11-10","untilDay":"\(until)","timeZone":"Asia/Tokyo","buckets":[],"sources":[],"pricing":{"status":"cached"}}
      """
    return try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
  }
  let a = EnvironmentUsage(id: "a", summary: try summary("2026-11-12"))
  let b = EnvironmentUsage(id: "b", summary: try summary("2026-11-11"))
  #expect(throws: UsageEnvironmentMergeError.differentWindow) {
    try UsageEnvironmentMerger.merge([a, b])
  }
  #expect(throws: UsageEnvironmentMergeError.duplicateEnvironment) {
    try UsageEnvironmentMerger.merge([a, a])
  }
}

@Test func multipleEnvironmentsRejectDifferentModelFilters() throws {
  func summary(_ filter: String) throws -> UsageResponse {
    let json = """
      {"contractVersion":6,"readAt":"2026-11-12T10:00:00Z","sinceDay":"2026-11-10","untilDay":"2026-11-12","timeZone":"Asia/Tokyo","modelFilter":{"include":[{"model":"\(filter)"}]},"buckets":[],"sources":[],"pricing":{"status":"cached"}}
      """
    return try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
  }
  let a = EnvironmentUsage(id: "a", summary: try summary("model-a"))
  let b = EnvironmentUsage(id: "b", summary: try summary("model-b"))
  #expect(throws: UsageEnvironmentMergeError.differentFilter) {
    try UsageEnvironmentMerger.merge([a, b])
  }
}

@Test func multipleEnvironmentsRejectUnknownSourceStates() throws {
  let json = """
    {"contractVersion":6,"readAt":"2026-11-12T10:00:00Z","sinceDay":"2026-11-10","untilDay":"2026-11-12","timeZone":"Asia/Tokyo","buckets":[],"sources":[{"status":"unknown"}],"pricing":{"status":"cached"}}
    """
  let summary = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
  #expect(throws: UsageEnvironmentMergeError.unsupportedSourceStatus) {
    try UsageEnvironmentMerger.merge([EnvironmentUsage(id: "a", summary: summary)])
  }
}

@Test func systemLanguageFollowsSupportedPreferencesAndChineseRegions() {
  #expect(UsageLanguage.system.resolved(preferred: ["fr-FR", "ja-JP"]) == .japanese)
  #expect(UsageLanguage.system.resolved(preferred: ["zh-Hans-CN"]) == .simplifiedChinese)
  #expect(UsageLanguage.system.resolved(preferred: ["zh-HK"]) == .traditionalChinese)
  #expect(UsageLanguage.system.resolved(preferred: ["zh-Hant-TW"]) == .traditionalChinese)
  #expect(UsageLanguage.system.resolved(preferred: ["fr-FR"]) == .english)
  #expect(UsageLanguage.japanese.resolved(preferred: ["en-US"]) == .japanese)
}

@Test func everyVisibleStringExistsInAllLanguages() {
  for language in [UsageLanguage.japanese, .english, .simplifiedChinese, .traditionalChinese] {
    for key in UsageStrings.Key.allCases {
      #expect(UsageStrings.text(key, language: language) != key.rawValue)
    }
  }
  #expect(UsageStrings.text(.loading, language: .english) == "Loading data…")
  #expect(UsageStrings.text(.show, language: .simplifiedChinese, "费用") == "显示费用")
  #expect(UsageStrings.text(.remaining, language: .japanese, "77") == "残り 77%")
}

@Test func snapshotLanguageRoundTripsAndOlderSnapshotFallsBackToSystem() throws {
  let snapshot = UsageSnapshot(
    processedTokens: 1, estimatedCostUSD: 2, limits: [], updatedAt: .now, status: .connected
  ).withLanguage(.traditionalChinese)
  let data = try JSONEncoder().encode(snapshot)
  #expect(try JSONDecoder().decode(UsageSnapshot.self, from: data).language == .traditionalChinese)
  var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  object.removeValue(forKey: "language")
  let old = try JSONSerialization.data(withJSONObject: object)
  #expect(try JSONDecoder().decode(UsageSnapshot.self, from: old).language == .system)
}

@Test func providerLimitLabelPreservesProviderAndNamedVariant() throws {
  let limit = try #require(
    UsageLimit(
      id: "one", label: "Claude Weekly · Fable", usedPercent: 20, providerName: "Claude",
      windowName: "Weekly · Fable"))
  #expect(limit.displayLabel(language: .japanese) == "Claude 週間 · Fable")
  #expect(limit.displayLabel(language: .simplifiedChinese) == "Claude 每周 · Fable")
  #expect(limit.displayLabel(language: .english) == "Claude Weekly · Fable")
}

@Test func compactPeriodsRemainReadableInEachLanguage() {
  #expect(UsagePeriod.week.shortLabel(language: .english) == "7d")
  #expect(UsagePeriod.week.shortLabel(language: .japanese) == "7日")
  #expect(UsagePeriod.week.shortLabel(language: .simplifiedChinese) == "7天")
  #expect(UsagePeriod.week.label(language: .english) == "7 days")
}

@Test func expiredSnapshotKeepsSelectedTabAndLanguage() {
  let now = Date(timeIntervalSince1970: 10_000)
  let snapshot = UsageSnapshot(
    processedTokens: 7, estimatedCostUSD: 1, limits: [], updatedAt: now.addingTimeInterval(-1801),
    status: .connected, tab: .limits, language: .traditionalChinese)
  let expired = LocalSnapshotClient.current(snapshot, now: now)
  #expect(expired.status == .disconnected)
  #expect(expired.tab == .limits)
  #expect(expired.language == .traditionalChinese)
}

@Test func loadingSnapshotKeepsLanguageAndSelection() {
  let snapshot = UsageSnapshot.loading(period: .week, tab: .tokens).withLanguage(.simplifiedChinese)
  let current = LocalSnapshotClient.current(snapshot, now: .now)
  #expect(current.status == .loading)
  #expect(current.language == .simplifiedChinese)
  #expect(current.tab == .tokens)
  #expect(current.period == .week)
  #expect(UsageStrings.text(.loading, language: current.language) == "正在获取数据…")
}

@Test func remoteEnvironmentRequiresHTTPSAndAnIdentity() throws {
  #expect(throws: ClientError.invalidOrigin) {
    try RemoteEnvironment(baseURL: URL(string: "http://example.test")!, environmentID: "host")
  }
  #expect(throws: ClientError.invalidOrigin) {
    try RemoteEnvironment(baseURL: URL(string: "https://example.test")!, environmentID: "")
  }
  #expect(throws: ClientError.invalidOrigin) {
    try RemoteEnvironment(
      baseURL: URL(string: "https://user:pass@example.test")!, environmentID: "host")
  }
  _ = try RemoteEnvironment(baseURL: URL(string: "https://example.test")!, environmentID: "host")
}

@Test func remoteMCPURLNormalizesToTheEnvironmentOrigin() throws {
  let remote = try RemoteEnvironment(
    baseURL: URL(string: "https://example.test/mcp")!, environmentID: "host")
  #expect(remote.baseURL.absoluteString == "https://example.test")
  #expect(throws: ClientError.invalidOrigin) {
    try RemoteEnvironment(
      baseURL: URL(string: "https://example.test/unexpected")!, environmentID: "host")
  }
}

@Test func remoteSnapshotKeepsItsScopeWhenChangingLanguageOrTab() throws {
  let snapshot = UsageSnapshot.disconnected.includingRemote()
  let changed = snapshot.selecting(.tokens).withLanguage(.japanese).withStatus(.partial)
  #expect(changed.includesRemote)
  let restored = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(changed))
  #expect(restored.includesRemote)
}

@Test func fullyUnpricedUsageIsNotShownAsZeroCost() throws {
  let json = """
    {"contractVersion":6,"buckets":[{"provider":"codex","totals":{"uncachedInputTokens":10,"cachedInputTokens":0,"cacheCreationTokens":0,"outputTokens":0},"costUsd":0,"unpricedRecords":1}],"sources":[{"status":"ok"}],"pricing":{"status":"cached"}}
    """
  let usage = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
  let snapshot = try UsageSummaryReducer.snapshot(usage, limits: [], updatedAt: .now)
  #expect(snapshot.estimatedCostUSD == nil)
  #expect(snapshot.hasUnpricedUsage)
  #expect(snapshot.status == .partial)
}
