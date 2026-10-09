import SwiftUI

/// Full-screen wait with centered shimmer copy and an optional turn timer.
struct WaitingForPlayersView: View {
  var message: String = "Waiting for other players"
  var endsAt: Date?

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)

      ShimmerText(text: message)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .pageHorizontalPadding()

      Spacer(minLength: 0)

      PhaseCountdown(endsAt: endsAt, style: .timer)
        .frame(maxWidth: .infinity, minHeight: Theme.Sizing.inputHeight, alignment: .leading)
        .frame(height: Theme.Spacing.s10, alignment: .bottom)
        .pageHorizontalPadding()
        .padding(.bottom, Theme.Spacing.s3)
    }
  }
}
