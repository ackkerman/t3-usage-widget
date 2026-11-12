import SwiftUI
import UsageCore

/// Shows the input, cache-read, cache-write and output values used by T3.
struct UsageCategoryBar: View {
  let categories: UsageCategories
  let metric: UsageTab
  let language: UsageLanguage

  private struct Entry {
    let name: String
    let value: Double
    let label: String
    let color: Color
  }

  private var entries: [Entry] {
    let colors: [Color] = [.gray, .gray.opacity(0.65), .gray.opacity(0.85), .primary]
    if metric == .tokens {
      let values: [(String, Int64)] = [
        (UsageStrings.text(.input, language: language), categories.input),
        (UsageStrings.text(.cacheRead, language: language), categories.cacheRead),
        (UsageStrings.text(.cacheWrite, language: language), categories.cacheWrite),
        (UsageStrings.text(.output, language: language), categories.output),
      ]
      return zip(values, colors).map { item, color in
        Entry(
          name: item.0, value: Double(item.1), label: UsageFormatting.tokens(item.1), color: color)
      }
    }
    let values: [(String, Double?)] = [
      (UsageStrings.text(.input, language: language), categories.inputCost),
      (UsageStrings.text(.cacheRead, language: language), categories.cacheReadCost),
      (UsageStrings.text(.cacheWrite, language: language), categories.cacheWriteCost),
      (UsageStrings.text(.output, language: language), categories.outputCost),
    ]
    return zip(values, colors).compactMap { item, color in
      item.1.map { Entry(name: item.0, value: $0, label: UsageFormatting.cost($0), color: color) }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(UsageStrings.text(metric == .tokens ? .tokensByType : .costByType, language: language))
        .font(.caption2)
      if entries.count == 4 {
        let total = entries.reduce(0) { $0 + $1.value }
        GeometryReader { geometry in
          HStack(spacing: 1) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, item in
              item.color.frame(
                width: total > 0 ? max(0, (geometry.size.width - 3) * item.value / total) : 0)
            }
          }.clipShape(Capsule())
        }.frame(height: 6)
        ForEach(0..<2) { row in
          HStack(spacing: 5) {
            ForEach((row * 2)..<(row * 2 + 2), id: \.self) { index in
              let item = entries[index]
              HStack(spacing: 2) {
                Circle().fill(item.color).frame(width: 4, height: 4)
                Text(item.name).lineLimit(1)
                Text(item.label).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
              }.frame(maxWidth: .infinity, alignment: .leading)
            }
          }.font(.system(size: 8)).foregroundStyle(.secondary)
        }
      } else {
        Text(UsageStrings.text(.breakdownUnavailable, language: language)).font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }
}
