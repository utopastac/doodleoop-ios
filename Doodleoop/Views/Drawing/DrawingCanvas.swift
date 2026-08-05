import SwiftUI
import UIKit

/// Up to 10 reversible actions (stroke commits + clear).
struct DrawingUndoStack {
  private enum Step: Equatable {
    case removeLastStroke
    case restore(Drawing)
  }

  private var steps: [Step] = []
  private let limit = 10

  var canUndo: Bool { !steps.isEmpty }

  mutating func registerStrokeAdded() {
    steps.append(.removeLastStroke)
    trim()
  }

  mutating func registerClear(before drawing: Drawing) {
    guard !drawing.isEmpty else { return }
    steps.append(.restore(drawing))
    trim()
  }

  mutating func undo(drawing: inout Drawing) {
    guard let step = steps.popLast() else { return }
    switch step {
    case .removeLastStroke:
      if !drawing.strokes.isEmpty {
        drawing.strokes.removeLast()
      }
    case .restore(let previous):
      drawing = previous
    }
  }

  mutating func reset() {
    steps.removeAll()
  }

  private mutating func trim() {
    if steps.count > limit {
      steps.removeFirst(steps.count - limit)
    }
  }
}

struct DrawingCanvas: View {
  @Binding var drawing: Drawing
  var tool: DrawingTool
  var colorHex: String
  var lineWidth: Double
  /// Optional override; defaults to the app-wide paper preference.
  var paperStyle: PaperStyle? = nil
  var onWillCommitStroke: (() -> Void)?

  @Environment(\.displayScale) private var displayScale
  @Environment(\.paperStyle) private var preferredPaperStyle

  @State private var currentStroke: Stroke?
  @State private var lastSampleTime: TimeInterval?
  @State private var lastSampleLocation: CGPoint?
  @State private var smoothedPenWidth: Double?
  @State private var bakedImage: UIImage?
  @State private var bakedStrokeCount = 0
  @State private var canvasSize: CGSize = .zero

  private var resolvedPaperStyle: PaperStyle { paperStyle ?? preferredPaperStyle }

  var body: some View {
    let isLiveErasing = currentStroke?.tool.isEraser == true

    ZStack {
      // Hide the bake while live-erasing so destinationOut can punch through ink in one canvas.
      if let bakedImage, !isLiveErasing {
        Image(uiImage: bakedImage)
          .resizable()
          .interpolation(.high)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      Canvas { context, size in
        if isLiveErasing {
          StrokeRenderer.drawDrawing(
            drawing,
            liveStroke: currentStroke,
            in: &context,
            size: size
          )
        } else if let currentStroke {
          // Only the in-progress stroke is redrawn while the finger moves.
          StrokeRenderer.draw(currentStroke, in: &context, size: size, live: true)
        }
      }
    }
    .paperSurface(resolvedPaperStyle, in: Rectangle())
    .background {
      GeometryReader { geo in
        Color.clear
          .onAppear { updateCanvasSize(geo.size) }
          .onChange(of: geo.size) { _, newSize in updateCanvasSize(newSize) }
      }
    }
    .onChange(of: drawing) { _, newDrawing in
      reconcileBake(with: newDrawing)
    }
    .onChange(of: resolvedPaperStyle) { _, _ in
      bakedImage = nil
      bakedStrokeCount = -1
      reconcileBake(with: drawing)
    }
    .overlay {
      // UIKit coalesced touches keep fast strokes dense; SwiftUI DragGesture cannot.
      StrokeTouchCapture(
        onSamples: { samples, size in
          for sample in samples {
            appendSample(sample.location, timestamp: sample.timestamp, in: size)
          }
        },
        onEnded: { location, size in
          finishStroke(at: location, in: size)
        }
      )
    }
  }

  private func appendSample(_ location: CGPoint, timestamp: TimeInterval, in size: CGSize) {
    let canvasWidth = max(size.width, 1)
    let canvasHeight = max(size.height, 1)

    let pointWidth = penPointWidth(
      at: location,
      now: timestamp,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight
    )

    let point = DrawPoint(
      x: location.x / canvasWidth,
      y: location.y / canvasHeight,
      lineWidth: pointWidth
    )

    if currentStroke == nil {
      currentStroke = Stroke(
        points: [point],
        lineWidth: lineWidth,
        tool: tool,
        colorHex: colorHex
      )
      lastSampleTime = timestamp
      lastSampleLocation = location
      smoothedPenWidth = pointWidth
      return
    }

    guard let last = currentStroke?.points.last else { return }
    let dx = (point.x - last.x) * canvasWidth
    let dy = (point.y - last.y) * canvasHeight
    let distance = hypot(dx, dy)
    // Keep real samples only — never invent chord midpoints (those force polygons).
    let minSpacing: CGFloat = 0.7

    if distance < minSpacing {
      if tool == .pen, var stroke = currentStroke, !stroke.points.isEmpty {
        stroke.points[stroke.points.count - 1].lineWidth = pointWidth
        currentStroke = stroke
      }
      lastSampleTime = timestamp
      lastSampleLocation = location
      return
    }

    currentStroke?.points.append(point)
    lastSampleTime = timestamp
    lastSampleLocation = location
  }

  private func finishStroke(at location: CGPoint, in size: CGSize) {
    if var stroke = currentStroke {
      let canvasWidth = max(size.width, 1)
      let canvasHeight = max(size.height, 1)
      let endWidth: Double? = {
        guard tool == .pen else { return nil }
        // Keep the live tip width — don't force a thin end blob.
        return max(0.6, smoothedPenWidth ?? lineWidth)
      }()
      let end = DrawPoint(
        x: location.x / canvasWidth,
        y: location.y / canvasHeight,
        lineWidth: endWidth
      )
      if let last = stroke.points.last,
         abs(last.x - end.x) < 0.0005,
         abs(last.y - end.y) < 0.0005 {
        stroke.points[stroke.points.count - 1].lineWidth = endWidth ?? last.lineWidth
      } else {
        stroke.points.append(end)
      }
      onWillCommitStroke?()
      drawing.strokes.append(stroke)
    }
    currentStroke = nil
    lastSampleTime = nil
    lastSampleLocation = nil
    smoothedPenWidth = nil
  }

  private func updateCanvasSize(_ size: CGSize) {
    let rounded = CGSize(width: size.width.rounded(), height: size.height.rounded())
    guard rounded != canvasSize else { return }
    canvasSize = rounded
    bakedImage = nil
    bakedStrokeCount = -1
    reconcileBake(with: drawing)
  }

  private func reconcileBake(with drawing: Drawing) {
    guard canvasSize.width > 1, canvasSize.height > 1 else { return }
    if drawing.strokes.isEmpty {
      bakedImage = nil
      bakedStrokeCount = 0
      return
    }
    guard drawing.strokes.count != bakedStrokeCount || bakedImage == nil else { return }
    bakedImage = StrokeRenderer.bake(
      drawing,
      size: canvasSize,
      scale: displayScale,
      paperStyle: resolvedPaperStyle
    )
    bakedStrokeCount = drawing.strokes.count
  }

  /// Pen only: map finger speed → brush width, with light smoothing.
  private func penPointWidth(
    at location: CGPoint,
    now: TimeInterval,
    canvasWidth: CGFloat,
    canvasHeight: CGFloat
  ) -> Double? {
    guard tool == .pen else { return nil }

    let base = lineWidth
    guard let lastTime = lastSampleTime, let lastLocation = lastSampleLocation else {
      return base * 1.15
    }

    let dt = max(now - lastTime, 1.0 / 240.0)
    let dx = location.x - lastLocation.x
    let dy = location.y - lastLocation.y
    let scale = 390 / max(min(canvasWidth, canvasHeight), 1)
    let speed = Double(hypot(dx, dy) * scale) / dt
    let target = StrokeRenderer.penWidth(base: base, speedPointsPerSecond: speed)
    let previous = smoothedPenWidth ?? base
    let blended = previous * 0.72 + target * 0.28
    smoothedPenWidth = blended
    return blended
  }
}

/// High-frequency finger samples via UIKit coalesced touches.
private struct StrokeTouchCapture: UIViewRepresentable {
  struct Sample {
    var location: CGPoint
    var timestamp: TimeInterval
  }

  var onSamples: ([Sample], CGSize) -> Void
  var onEnded: (CGPoint, CGSize) -> Void

  func makeUIView(context: Context) -> TouchView {
    let view = TouchView()
    view.isMultipleTouchEnabled = false
    view.backgroundColor = .clear
    view.isOpaque = false
    view.onSamples = onSamples
    view.onEnded = onEnded
    return view
  }

  func updateUIView(_ uiView: TouchView, context: Context) {
    uiView.onSamples = onSamples
    uiView.onEnded = onEnded
  }

  final class TouchView: UIView {
    var onSamples: (([Sample], CGSize) -> Void)?
    var onEnded: ((CGPoint, CGSize) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      emit(touches, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      emit(touches, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      emit(touches, event: event)
      if let touch = touches.first {
        onEnded?(touch.location(in: self), bounds.size)
      }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      touchesEnded(touches, with: event)
    }

    private func emit(_ touches: Set<UITouch>, event: UIEvent?) {
      guard let touch = touches.first else { return }
      let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
      let samples = coalesced.map {
        Sample(location: $0.location(in: self), timestamp: $0.timestamp)
      }
      onSamples?(samples, bounds.size)
    }
  }
}
