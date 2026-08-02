import SwiftUI

struct DrawingCanvas: View {
  @Binding var drawing: Drawing
  @State private var currentStroke: Stroke?

  var body: some View {
    Canvas { context, size in
      for stroke in drawing.strokes + (currentStroke.map { [$0] } ?? []) {
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
    .overlay {
      GeometryReader { geo in
        Color.clear.contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                let point = DrawPoint(
                  x: value.location.x / max(geo.size.width, 1),
                  y: value.location.y / max(geo.size.height, 1)
                )
                if currentStroke == nil {
                  currentStroke = Stroke(points: [point])
                } else {
                  currentStroke?.points.append(point)
                }
              }
              .onEnded { _ in
                if let stroke = currentStroke {
                  drawing.strokes.append(stroke)
                }
                currentStroke = nil
              }
          )
      }
    }
  }
}

struct DrawingView: View {
  @EnvironmentObject private var session: GameSession
  @State private var drawing = Drawing.empty

  var body: some View {
    let state = session.state
    let prompt: String = {
      guard let state,
            let pad = state.pad(inFrontOf: session.localPlayerId),
            let last = pad.steps.last else { return session.state?.category ?? "" }
      switch last {
      case .prompt(let text):
        return text
      case .guess(_, let text):
        return text
      case .drawing:
        return state.category
      }
    }()

    VStack(spacing: 16) {
      Text("Draw")
        .font(.largeTitle.weight(.black))
      Text(prompt)
        .font(.title2.weight(.semibold))
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.teal)

      DrawingCanvas(drawing: $drawing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)

      HStack {
        Button("Clear") { drawing = .empty }
        Spacer()
        Button("Done") {
          session.submitDrawing(drawing)
          drawing = .empty
        }
        .buttonStyle(PrimaryButtonStyle(color: Theme.coral))
        .frame(width: 140)
        .disabled(drawing.isEmpty || (state?.submittedPlayerIds.contains(session.localPlayerId) ?? false))
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 12)
    }
    .padding(.top, 20)
    .background(Theme.paper.ignoresSafeArea())
  }
}
