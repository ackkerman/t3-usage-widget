import AppIntents
import SwiftUI
import UsageCore
import WidgetKit

/// App Intent buttons change the selected view without launching the host app.
struct UsageTabBar: View {
  let selected: UsageTab
  let family: WidgetFamily
  let language: UsageLanguage

  var body: some View {
    HStack(spacing: 1) {
      ForEach(UsageTab.allCases, id: \.rawValue) { tab in
        Button(intent: ChangeUsageTabIntent(tab)) {
          Image(systemName: tab.systemImage)
            .font(
              .system(
                size: family == .systemSmall ? 9 : 10,
                weight: selected == tab ? .semibold : .regular)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(
              selected == tab ? Color.primary.opacity(0.12) : .clear,
              in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(UsageStrings.text(.show, language: language, tab.label(language: language)))
        .accessibilityLabel(
          Text(UsageStrings.text(.show, language: language, tab.label(language: language)))
        )
        .accessibilityAddTraits(selected == tab ? .isSelected : [])
      }
    }
    .padding(2)
    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
  }
}

/// Compact period buttons follow T3's four available windows.
struct UsagePeriodBar: View {
  let selected: UsagePeriod
  let family: WidgetFamily
  let language: UsageLanguage

  var body: some View {
    HStack(spacing: 1) {
      ForEach(UsagePeriod.allCases) { period in
        Button(intent: ChangeUsagePeriodIntent(period)) {
          Text(
            family == .systemSmall
              ? period.shortLabel(language: language) : period.label(language: language)
          )
          .font(
            .system(
              size: family == .systemSmall ? 8 : 9,
              weight: selected == period ? .semibold : .regular)
          )
          .frame(maxWidth: .infinity)
          .padding(.vertical, 2)
          .background(
            selected == period ? Color.primary.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          Text(UsageStrings.text(.show, language: language, period.label(language: language)))
        )
        .accessibilityAddTraits(selected == period ? .isSelected : [])
      }
    }
    .padding(1)
    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
  }
}
