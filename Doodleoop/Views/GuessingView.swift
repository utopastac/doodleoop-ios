import SwiftUI

struct GuessingView: View {
  @EnvironmentObject private var session: GameSession
  @State private var guess = ""
  /// Width ÷ height from the tallest layout seen (keyboard dismissed).
  @State private var drawingAspect: CGFloat?

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
      .pageHorizontalPadding()

      Text("What is this a drawing of?")
        .themeText(.label)
        .foregroundStyle(Theme.Text.secondary)

      if let drawing {
        GeometryReader { geo in
          let aspect = drawingAspect ?? (geo.size.width / max(geo.size.height, 1))
          let width = min(geo.size.width, geo.size.height * aspect)
          let height = width / aspect

          ReadOnlyDrawingView(drawing: drawing)
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { considerDrawingAspect(geo.size) }
            .onChange(of: geo.size) { _, size in considerDrawingAspect(size) }
        }
        .pageHorizontalPadding()
      } else {
        Spacer()
        ProgressView("Waiting for drawing…")
          .tint(Theme.Accent.default)
        Spacer()
      }

      TextField("Your guess", text: $guess)
        .themeText(.label)
        .textFieldStyle(.roundedBorder)
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
    .paperBackground(.plain)
    .pageMargins()
    .task(id: state?.phaseEndsAt) {
      await autoSubmitWhenTimerExpires(endsAt: state?.phaseEndsAt)
    }
  }

  /// Prefer the roomiest (tallest) proposal so the keyboard shrinks the sheet uniformly.
  private func considerDrawingAspect(_ size: CGSize) {
    guard size.width > 1, size.height > 1 else { return }
    let aspect = size.width / size.height
    if let drawingAspect {
      if aspect < drawingAspect {
        self.drawingAspect = aspect
      }
    } else {
      drawingAspect = aspect
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
    .paperSurface(.crosses, in: Rectangle())
  }
}

struct AvatarBadge: View {
  let drawing: Drawing
  var size: CGFloat = Theme.Sizing.avatarMd

  var body: some View {
    Group {
      if drawing.isEmpty {
        Circle()
          .fill(Theme.Background.tertiary)
          .overlay {
            Image(systemName: "person.fill")
              .font(.system(size: size * 0.4))
              .foregroundStyle(Theme.Text.tertiary)
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
        .paperSurface(.crosses, in: Circle())
      }
    }
    .frame(width: size, height: size)
    .overlay(Circle().stroke(Theme.Stroke.subtle, lineWidth: Theme.Borders.thin))
  }
}
