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

    VStack(spacing: 16) {
      Text("Guess")
        .font(.largeTitle.weight(.black))
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
      .disabled(guess.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.top, 20)
    .background(Theme.paper.ignoresSafeArea())
  }
}

struct ReadOnlyDrawingView: View {
  let drawing: Drawing

  var body: some View {
    Canvas { context, size in
      for stroke in drawing.strokes {
        guard let first = stroke.points.first else { continue }
        var path = Path()
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in stroke.points.dropFirst() {
          path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        context.stroke(
          path,
          with: .color(Theme.ink),
          style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
        )
      }
    }
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}
