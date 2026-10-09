import SwiftUI

/// Host-gated pause between drawing and guessing turns.
struct PassingView: View {
  @Environment(GameSession.self) private var session

  private var nextIsDraw: Bool {
    session.state?.isDrawTurn ?? true
  }

  private var startTitle: String {
    nextIsDraw ? "Start drawing" : "Start guessing"
  }

  var body: some View {
    VStack(spacing: 0) {
      LeaveToolbarBand()
        .gridBand()

      Spacer(minLength: 0)

      VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
        Text(nextIsDraw ? "Get ready to draw" : "Get ready to guess")
          .themeText(.heading)
          .foregroundStyle(Theme.Text.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityAddTraits(.isHeader)

        Text(
          nextIsDraw
            ? "Everyone draws the guess sitting in front of them."
            : "Everyone guesses the drawing sitting in front of them."
        )
        .themeText(.body)
        .foregroundStyle(Theme.Text.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .pageHorizontalPadding()

      Spacer(minLength: 0)

      footer
    }
    .paperBackground()
    .pageMargins()
  }

  @ViewBuilder
  private var footer: some View {
    Group {
      if session.isHost {
        Button(DoodleLabel.bracketed(startTitle)) {
          session.startNextTurn()
        }
        .doodleButton(.primary)
      } else {
        ShimmerText(text: "Waiting for the host to start")
          .frame(maxWidth: .infinity, minHeight: Theme.Spacing.s9, alignment: .leading)
      }
    }
    .pageHorizontalPadding()
    .padding(.bottom, Theme.Spacing.s3)
  }
}
