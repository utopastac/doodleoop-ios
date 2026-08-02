import SwiftUI

struct GuessingView: View {
  @EnvironmentObject private var session: GameSession
  @State private var guess = ""

  var body: some View {
    let drawing: Drawing? = {
      guard let state = session.state,
            let pad = state.pad(inFrontOf: session.localPlayerId),
            case .drawing(_, let art) = pad.steps.last else { return nil }
      return art
    }()

    let state = session.state

    VStack(spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        Text("Guess")
          .font(Theme.Fonts.largeTitle)
        Spacer()
        PhaseCountdown(endsAt: state?.phaseEndsAt)
      }
      .padding(.horizontal, 20)

      Text("What is this a drawing of?")
        .foregroundStyle(.secondary)

      if let drawing {
        ReadOnlyDrawingView(drawing: drawing)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.horizontal, 16)
      } else {
        Spacer()
        ProgressView("Waiting for drawing…")
        Spacer()
      }

      TextField("Your guess", text: $guess)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 20)

      Button("Submit guess") {
        session.submitGuess(guess)
        guess = ""
      }
      .buttonStyle(PrimaryButtonStyle(color: Theme.teal))
      .padding(.horizontal, 20)
      .padding(.bottom, 12)
      .disabled(
        guess.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || (state?.submittedPlayerIds.contains(session.localPlayerId) ?? false)
      )
    }
    .padding(.top, 20)
    .background(Theme.paper.ignoresSafeArea())
    .task(id: state?.phaseEndsAt) {
      await autoSubmitWhenTimerExpires(endsAt: state?.phaseEndsAt)
    }
  }

  private func autoSubmitWhenTimerExpires(endsAt: Date?) async {
    guard let endsAt else { return }
    let delay = endsAt.timeIntervalSinceNow
    if delay > 0 {
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    guard !Task.isCancelled else { return }
    let trimmed = guess.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let state = session.state,
          state.phase == .guessing,
          !state.submittedPlayerIds.contains(session.localPlayerId),
          !trimmed.isEmpty else { return }
    session.submitGuess(trimmed)
    guess = ""
  }
}

struct ReadOnlyDrawingView: View {
  let drawing: Drawing

  var body: some View {
    Canvas { context, size in
      StrokeRenderer.drawDrawing(drawing, in: &context, size: size)
    }
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

struct AvatarBadge: View {
  let drawing: Drawing
  var size: CGFloat = 40

  var body: some View {
    Group {
      if drawing.isEmpty {
        Circle()
          .fill(Theme.ink.opacity(0.08))
          .overlay {
            Image(systemName: "person.fill")
              .font(.system(size: size * 0.4))
              .foregroundStyle(Theme.ink.opacity(0.35))
          }
      } else {
        Canvas { context, canvasSize in
          let scale = canvasSize.width / 280
          StrokeRenderer.drawDrawing(
            drawing,
            in: &context,
            size: canvasSize,
            widthScale: scale
          )
        }
        .background(Color.white)
        .clipShape(Circle())
      }
    }
    .frame(width: size, height: size)
    .overlay(Circle().stroke(Theme.ink.opacity(0.12), lineWidth: 1))
  }
}
