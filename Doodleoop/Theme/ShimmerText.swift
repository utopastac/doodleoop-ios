import SwiftUI

/// Status copy with a soft highlight that sweeps across the glyphs.
struct ShimmerText: View {
  let text: String
  var style: Theme.TextStyle = .body
  var base: Color = Theme.Text.secondary
  var highlight: Color = Theme.Paper.white

  private let period: TimeInterval = 2.2

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
      let phase = context.date.timeIntervalSinceReferenceDate
        .truncatingRemainder(dividingBy: period) / period

      Text(text)
        .themeText(style)
        .foregroundStyle(base)
        .overlay {
          GeometryReader { geo in
            let band = geo.size.width * 0.55
            let travel = geo.size.width + band
            let x = -band + CGFloat(phase) * travel
            LinearGradient(
              colors: [
                .clear,
                highlight.opacity(0.9),
                .clear,
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
            .frame(width: band)
            .offset(x: x)
          }
          .mask {
            Text(text)
              .themeText(style)
          }
        }
    }
    .accessibilityLabel(text)
  }
}
