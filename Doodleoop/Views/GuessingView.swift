import SwiftUI

struct GuessingView: View {
  @Environment(GameSession.self) private var session
  @State private var guess = ""
  /// Optimistic submit so joiners see the wait UI before `syncState` lands.
  @State private var locallySubmittedForPlayerId: String?

  var body: some View {
    let state = session.state
    let hasSubmitted = locallySubmittedForPlayerId == session.localPlayerId
      || (state?.submittedPlayerIds.contains(session.localPlayerId) ?? false)

    Group {
      if hasSubmitted {
        WaitingForPlayersView(endsAt: state?.phaseEndsAt)
      } else {
        guessingContent(state: state)
      }
    }
    .paperBackground()
    .pageMargins()
    .task(id: state?.phaseEndsAt) {
      await autoSubmitWhenTimerExpires(endsAt: state?.phaseEndsAt)
    }
  }

  private func guessingContent(state: GameState?) -> some View {
    let drawing: Drawing? = {
      guard let state,
            let pad = state.pad(inFrontOf: session.localPlayerId),
            case .drawing(_, let art) = pad.steps.last else { return nil }
      return art
    }()

    return VStack(spacing: Theme.Spacing.s4) {
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
        ShimmerText(text: "Waiting for drawing")
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
        Spacer()
      }

      DoodleTextField(placeholder: "Your guess", text: $guess)
        .pageHorizontalPadding()
        .onChange(of: guess) { _, next in
          let capped = String(next.prefix(GamePartyLimits.maxGuessLength))
          if capped != next { guess = capped }
        }

      Button(DoodleLabel.bracketed("Submit guess")) {
        commitGuess()
      }
      .doodleButton(.primary)
      .pageHorizontalPadding()
      .padding(.bottom, Theme.Spacing.s3)
      .disabled(guess.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityIdentifier("submit-guess")
    }
    .padding(.top, Theme.Spacing.s5)
  }

  private func commitGuess() {
    let trimmed = guess.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    locallySubmittedForPlayerId = session.localPlayerId
    session.submitGuess(trimmed)
    guess = ""
  }

  private func autoSubmitWhenTimerExpires(endsAt: Date?) async {
    guard await PhaseTimer.waitForExpiry(endsAt: endsAt) else { return }
    let trimmed = guess.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let state = session.state,
          state.phase == .guessing,
          locallySubmittedForPlayerId != session.localPlayerId,
          !state.submittedPlayerIds.contains(session.localPlayerId),
          !trimmed.isEmpty else { return }
    commitGuess()
  }
}
