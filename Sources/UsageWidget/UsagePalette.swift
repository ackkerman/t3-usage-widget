import SwiftUI

/// Matches the provider accents in T3's usage charts.
enum UsagePalette {
  static func provider(_ id: String) -> Color {
    switch id.lowercased() {
    case "claude", "claude code": return Color(red: 0.85, green: 0.47, blue: 0.34)
    case "opencode": return Color(red: 0.36, green: 0.61, blue: 0.74)
    case "antigravity": return Color(red: 0.55, green: 0.48, blue: 0.82)
    default: return .primary
    }
  }
}
