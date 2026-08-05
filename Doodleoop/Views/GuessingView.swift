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
    .paperBackground()
    .pageMargins()
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
  /// Width the strokes were authored against — the in-game square canvas.
  static let referenceWidth: CGFloat = 354

  let drawing: Drawing
  /// 0…1 — how much of the drawing has been replayed, stroke by stroke.
  var progress: Double = 1
  /// Thins the ink in proportion to the canvas, so thumbnails don't read as marker pen.
  var scalesStrokeWidth: Bool = false
  /// When false the strokes sit straight on the surrounding surface (rows, tiles).
  var showsPaper: Bool = true

  var body: some View {
    let canvas = StrokeReplayCanvas(
      drawing: drawing,
      progress: progress,
      scalesStrokeWidth: scalesStrokeWidth
    )
    return Group {
      if showsPaper {
        canvas.paperSurface(in: Rectangle())
      } else {
        canvas
      }
    }
  }
}

/// `Animatable` so SwiftUI interpolates `progress` and repaints the canvas each frame.
private struct StrokeReplayCanvas: View, Animatable {
  var drawing: Drawing
  var progress: Double
  var scalesStrokeWidth: Bool = false

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    Canvas { context, size in
      let widthScale = scalesStrokeWidth
        ? size.width / ReadOnlyDrawingView.referenceWidth
        : 1
      StrokeRenderer.drawDrawing(
        drawing,
        in: &context,
        size: size,
        widthScale: widthScale,
        progress: progress
      )
    }
  }
}

/// Instagram-style peek zoom: pinch to magnify in place, let go and it springs back.
///
/// Everything lives in `@GestureState`, which SwiftUI resets on its own when the
/// fingers lift — so the zoom has no state that can be left stuck.
struct ZoomableDrawingView: View {
  let drawing: Drawing
  var progress: Double = 1

  private static let springBack = Transaction(animation: Theme.Motion.reveal)

  @GestureState(resetTransaction: springBack) private var zoom: CGFloat = 1
  @GestureState(resetTransaction: springBack) private var anchor: UnitPoint = .center
  @GestureState(resetTransaction: springBack) private var pan: CGSize = .zero

  var body: some View {
    ReadOnlyDrawingView(drawing: drawing, progress: progress)
      .scaleEffect(zoom, anchor: anchor)
      .offset(pan)
      // Lifts the drawing above neighbouring steps while it's magnified.
      .zIndex(zoom > 1 ? 1 : 0)
      .simultaneousGesture(peekZoom)
  }

  private var peekZoom: some Gesture {
    MagnifyGesture()
      .updating($zoom) { value, state, _ in
        state = max(1, value.magnification)
      }
      .updating($anchor) { value, state, _ in
        state = value.startAnchor
      }
      .simultaneously(
        with: DragGesture(minimumDistance: 0)
          .updating($pan) { value, state, _ in
            // Follows the fingers only once a pinch is under way, so a plain
            // swipe still scrolls the page it sits in.
            guard zoom > 1 else { return }
            state = value.translation
          }
      )
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
        .paperSurface(in: Circle())
      }
    }
    .frame(width: size, height: size)
    .overlay(Circle().stroke(Theme.Stroke.subtle, lineWidth: Theme.Borders.thin))
  }
}
