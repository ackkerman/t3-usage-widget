import Foundation
import UsageCore

@main struct Probe {
  static func main() async {
    do {
      let result: UsageSnapshot
      if CommandLine.arguments.contains("--bridge") {
        result = await LocalSnapshotClient.read()
      } else {
        let args = CommandLine.arguments
        let selected =
          args.firstIndex(of: "--period").flatMap { index in
            index + 1 < args.count ? UsagePeriod(rawValue: args[index + 1]) : nil
          } ?? .month
        result = try await T3UsageClient().read(period: selected)
      }
      print(
        "usage available: \(result.processedTokens != nil); cost available: \(result.estimatedCostUSD != nil); limit windows: \(result.limits.count); status: \(result.status)"
      )
      if result.status == .disconnected { exit(1) }
    } catch {
      print("usage read failed: \(error)")
      exit(1)
    }
  }
}
