import Charts
import SwiftUI
import UsageCore

/// Renders T3's provider series from real bucket data, including empty periods.
struct UsageSeriesChart: View {
  let snapshot: UsageSnapshot
  let metric: UsageTab
  let compact: Bool

  var body: some View {
    let samples = UsageChartData.samples(snapshot)
    if samples.isEmpty {
      Text(UsageStrings.text(.noData, language: snapshot.language)).font(.caption2).foregroundStyle(
        .secondary
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      Chart(samples) { point in
        if let amount = metric == .tokens ? Double(point.tokens) : point.costUSD {
          let series = metric == .tokens ? point.provider : "\(point.provider)-\(point.costSegment)"
          AreaMark(
            x: .value(UsageStrings.text(.chartDate, language: snapshot.language), point.date),
            y: .value(UsageStrings.text(.chartValue, language: snapshot.language), amount),
            series: .value(UsageStrings.text(.chartProvider, language: snapshot.language), series),
            stacking: .unstacked
          )
          .interpolationMethod(.monotone)
          .foregroundStyle(UsagePalette.provider(point.provider).opacity(0.14))
          LineMark(
            x: .value(UsageStrings.text(.chartDate, language: snapshot.language), point.date),
            y: .value(UsageStrings.text(.chartValue, language: snapshot.language), amount),
            series: .value(UsageStrings.text(.chartProvider, language: snapshot.language), series)
          )
          .interpolationMethod(.monotone)
          .foregroundStyle(UsagePalette.provider(point.provider))
          .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
      }
      .chartLegend(.hidden)
      .chartXAxis(compact ? .hidden : .automatic)
      .chartYAxis(compact ? .hidden : .automatic)
      .accessibilityLabel(
        Text(
          UsageStrings.text(
            metric == .tokens ? .chartTokens : .chartCost, language: snapshot.language)))
    }
  }
}
