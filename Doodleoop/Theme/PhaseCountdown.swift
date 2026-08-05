import SwiftUI

/// Countdown synced to the host’s `phaseEndsAt`.
struct PhaseCountdown: View {
  let endsAt: Date?
  /// Drawing page uses a larger mono timer; other screens keep the default.
  var style: Theme.TextStyle = .subheading
  var urgentColor: Color = Theme.Accent.default
  var normalColor: Color = Theme.Text.primary

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { context in
      let remaining = Self.remainingSeconds(until: endsAt, now: context.date)
      Text(Self.format(remaining))
        .themeText(style)
        .foregroundStyle(remaining <= 5 ? urgentColor : normalColor)
        .accessibilityLabel("\(remaining) seconds remaining")
    }
  }

  static func remainingSeconds(until endsAt: Date?, now: Date = Date()) -> Int {
    guard let endsAt else { return 0 }
    return max(0, Int(ceil(endsAt.timeIntervalSince(now))))
  }

  /// `MM.SS` — matches Figma drawing-page timer (`00.45`).
  static func format(_ totalSeconds: Int) -> String {
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d.%02d", minutes, seconds)
  }
}
