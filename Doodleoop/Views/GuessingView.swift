import SwiftUI

struct GuessingView: View {
  @Environment(GameSession.self) private var session
  @State private var guess = ""

  var body: some View {
    let drawing: Drawing? = {
      guard let state = session.state,
            let pad = state.pad(inFrontOf: session.localPlayerId),
            case .drawing(_, let art) = pad.steps.last else { return nil }
      return art
    }()

    let state = session.state

    VStack(spacing: Theme.Spacing.s4) {
      HStack(alignment: .firstTextBaseline) {
        Text("Guess")
          .themeText(.heading)
          .foregroundStyle(Theme.Text.primary)
        Spacer()
        PhaseCountdown(endsAt: state?.phaseEndsAt)
      }
      .padding(.trailing, Theme.Sizing.leaveButtonReserve)
      .pageHorizontalPadding()

      Text("What is this a drawing of?")
        .themeText(.label)
        .foregroundStyle(Theme.Text.secondary)

      if let drawing {
        GeometryReader { geo in
          let side = min(geo.size.width, geo.size.height)
          ZoomableDrawingView(drawing: drawing)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .pageHorizontalPadding()
      } else {
        Spacer()
        ProgressView("Waiting for drawing…")
          .tint(Theme.Accent.default)
        Spacer()
      }

      DoodleTextField(placeholder: "Your guess", text: $guess)
        .pageHorizontalPadding()

      Button(DoodleLabel.bracketed("Submit guess")) {
        session.submitGuess(guess)
        guess = ""
      }
      .doodleButton(.primary)
      .pageHorizontalPadding()
      .padding(.bottom, Theme.Spacing.s3)
      .disabled(
        guess.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || (state?.submittedPlayerIds.contains(session.localPlayerId) ?? false)
      )
    }
    .padding(.top, Theme.Spacing.s5)
    .paperBackground()
    .pageMargins()
    .task(id: state?.phaseEndsAt) {
      await autoSubmitWhenTimerExpires(endsAt: state?.phaseEndsAt)
    }
  }

  private func autoSubmitWhenTimerExpires(endsAt: Date?) async {
    guard await PhaseTimer.waitForExpiry(endsAt: endsAt) else { return }
    let trimmed = guess.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let state = session.state,
          state.phase == .guessing,
          !state.submittedPlayerIds.contains(session.localPlayerId),
          !trimmed.isEmpty else { return }
    session.submitGuess(trimmed)
    guess = ""
  }
}
