import SwiftUI
import UIKit

enum StrokeRenderer {
  static func canvasPoints(for stroke: Stroke, size: CGSize) -> [CGPoint] {
    stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
  }

  /// Slow → thicker, fast → thinner. Speed in points/sec on the canvas.
  static func penWidth(base: Double, speedPointsPerSecond: Double) -> Double {
    let minFactor = 0.32
    let maxFactor = 1.65
    let capped = min(max(speedPointsPerSecond, 0), 1600)
    let t = capped / 1600
    let eased = t * t * (3 - 2 * t)
    return max(0.6, base * (maxFactor - (maxFactor - minFactor) * eased))
  }

  /// Catmull-Rom spline as cubic Béziers — smooth through sparse finger samples.
  static func smoothPath(from points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }

    if points.count == 1 {
      path.addEllipse(in: CGRect(x: first.x - 0.5, y: first.y - 0.5, width: 1, height: 1))
      return path
    }

    if points.count == 2 {
      path.move(to: first)
      path.addLine(to: points[1])
      return path
    }

    path.move(to: first)
    for index in 0..<(points.count - 1) {
      let p0 = points[max(index - 1, 0)]
      let p1 = points[index]
      let p2 = points[index + 1]
      let p3 = points[min(index + 2, points.count - 1)]
      let c1 = CGPoint(
        x: p1.x + (p2.x - p0.x) / 6,
        y: p1.y + (p2.y - p0.y) / 6
      )
      let c2 = CGPoint(
        x: p2.x - (p3.x - p1.x) / 6,
        y: p2.y - (p3.y - p1.y) / 6
      )
      path.addCurve(to: p2, control1: c1, control2: c2)
    }
    return path
  }

  private static func catmullRom(
    _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat
  ) -> CGPoint {
    let t2 = t * t
    let t3 = t2 * t
    return CGPoint(
      x: 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t
        + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
        + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
      y: 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t
        + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
        + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
    )
  }

  private static func catmullRom(
    _ w0: CGFloat, _ w1: CGFloat, _ w2: CGFloat, _ w3: CGFloat, _ t: CGFloat
  ) -> CGFloat {
    let t2 = t * t
    let t3 = t2 * t
    return 0.5 * ((2 * w1) + (-w0 + w2) * t
      + (2 * w0 - 5 * w1 + 4 * w2 - w3) * t2
      + (-w0 + 3 * w1 - 3 * w2 + w3) * t3)
  }

  /// Soften finger jitter before fitting the spline.
  private static func chaikin(
    points: [CGPoint],
    widths: [CGFloat],
    iterations: Int
  ) -> (points: [CGPoint], widths: [CGFloat]) {
    var pts = points
    var wds = widths
    guard pts.count >= 3, pts.count == wds.count, iterations > 0 else { return (pts, wds) }

    for _ in 0..<iterations {
      var nextPts: [CGPoint] = [pts[0]]
      var nextWds: [CGFloat] = [wds[0]]
      for index in 0..<(pts.count - 1) {
        let p = pts[index]
        let q = pts[index + 1]
        let wp = wds[index]
        let wq = wds[index + 1]
        nextPts.append(CGPoint(x: 0.75 * p.x + 0.25 * q.x, y: 0.75 * p.y + 0.25 * q.y))
        nextWds.append(0.75 * wp + 0.25 * wq)
        nextPts.append(CGPoint(x: 0.25 * p.x + 0.75 * q.x, y: 0.25 * p.y + 0.75 * q.y))
        nextWds.append(0.25 * wp + 0.75 * wq)
      }
      nextPts.append(pts[pts.count - 1])
      nextWds.append(wds[wds.count - 1])
      pts = nextPts
      wds = nextWds
    }
    return (pts, wds)
  }

  private static func resampledStroke(
    points: [CGPoint],
    widths: [CGFloat],
    spacing: CGFloat,
    chaikinIterations: Int
  ) -> (points: [CGPoint], widths: [CGFloat]) {
    guard points.count >= 2, points.count == widths.count else {
      return (points, widths)
    }

    let smoothed = chaikin(points: points, widths: widths, iterations: chaikinIterations)
    var outPoints: [CGPoint] = [smoothed.points[0]]
    var outWidths: [CGFloat] = [smoothed.widths[0]]

    for index in 0..<(smoothed.points.count - 1) {
      let p0 = smoothed.points[max(index - 1, 0)]
      let p1 = smoothed.points[index]
      let p2 = smoothed.points[index + 1]
      let p3 = smoothed.points[min(index + 2, smoothed.points.count - 1)]
      let w0 = smoothed.widths[max(index - 1, 0)]
      let w1 = smoothed.widths[index]
      let w2 = smoothed.widths[index + 1]
      let w3 = smoothed.widths[min(index + 2, smoothed.widths.count - 1)]

      let segmentLength = hypot(p2.x - p1.x, p2.y - p1.y)
      let steps = max(1, Int(ceil(segmentLength / max(spacing, 0.5))))

      for step in 1...steps {
        let t = CGFloat(step) / CGFloat(steps)
        outPoints.append(catmullRom(p0, p1, p2, p3, t))
        outWidths.append(max(0.5, catmullRom(w0, w1, w2, w3, t)))
      }
    }

    return (outPoints, outWidths)
  }

  private struct PenRibbon {
    var body: Path
    var startCap: CGRect?
    var endCap: CGRect?
  }

  /// Filled ribbon body + separate round caps (caps must not share a path — overlap holes out).
  private static func variableWidthRibbon(
    points: [CGPoint],
    widths: [CGFloat],
    live: Bool
  ) -> PenRibbon {
    guard !points.isEmpty else { return PenRibbon(body: Path()) }

    if points.count == 1 {
      let r = max(0.4, widths[0] / 2)
      let rect = CGRect(
        x: points[0].x - r, y: points[0].y - r, width: r * 2, height: r * 2
      )
      return PenRibbon(body: Path(ellipseIn: rect))
    }

    let spacing: CGFloat = live ? 2.8 : 1.4
    let sampled = resampledStroke(
      points: points,
      widths: widths,
      spacing: spacing,
      chaikinIterations: live ? 1 : 2
    )
    let pts = sampled.points
    let wds = sampled.widths
    guard pts.count >= 2 else { return PenRibbon(body: Path()) }

    var left: [CGPoint] = []
    var right: [CGPoint] = []
    left.reserveCapacity(pts.count)
    right.reserveCapacity(pts.count)

    for index in pts.indices {
      let tangent: CGPoint
      if index == 0 {
        tangent = CGPoint(x: pts[1].x - pts[0].x, y: pts[1].y - pts[0].y)
      } else if index == pts.count - 1 {
        tangent = CGPoint(x: pts[index].x - pts[index - 1].x, y: pts[index].y - pts[index - 1].y)
      } else {
        tangent = CGPoint(x: pts[index + 1].x - pts[index - 1].x, y: pts[index + 1].y - pts[index - 1].y)
      }

      let length = hypot(tangent.x, tangent.y)
      let nx: CGFloat
      let ny: CGFloat
      if length < 0.001 {
        nx = 0
        ny = 1
      } else {
        nx = -tangent.y / length
        ny = tangent.x / length
      }

      let radius = max(0.35, wds[index] / 2)
      left.append(CGPoint(x: pts[index].x + nx * radius, y: pts[index].y + ny * radius))
      right.append(CGPoint(x: pts[index].x - nx * radius, y: pts[index].y - ny * radius))
    }

    var body = Path()
    body.move(to: left[0])
    for point in left.dropFirst() {
      body.addLine(to: point)
    }
    body.addLine(to: right[right.count - 1])
    for point in right.dropLast().reversed() {
      body.addLine(to: point)
    }
    body.closeSubpath()

    let startR = max(0.35, wds[0] / 2)
    let endR = max(0.35, wds[wds.count - 1] / 2)
    let start = pts[0]
    let end = pts[pts.count - 1]

    return PenRibbon(
      body: body,
      startCap: CGRect(x: start.x - startR, y: start.y - startR, width: startR * 2, height: startR * 2),
      endCap: CGRect(x: end.x - endR, y: end.y - endR, width: endR * 2, height: endR * 2)
    )
  }

  static func draw(
    _ stroke: Stroke,
    in context: inout GraphicsContext,
    size: CGSize,
    widthScale: CGFloat = 1,
    live: Bool = false
  ) {
    let points = canvasPoints(for: stroke, size: size)
    guard !points.isEmpty else { return }

    let width = max(0.8, stroke.lineWidth * widthScale)
    let color = Color(drawingHex: stroke.colorHex).opacity(stroke.tool.opacity)
    let path = smoothPath(from: points)
    let cap: CGLineCap = stroke.tool.usesFlatTip ? .square : .round
    let style = StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: .round)

    switch stroke.tool {
    case .pen:
      let widths: [CGFloat] = stroke.points.map { point in
        CGFloat(max(0.6, (point.lineWidth ?? stroke.lineWidth) * widthScale))
      }
      let ribbon = variableWidthRibbon(points: points, widths: widths, live: live)
      let fillStyle = FillStyle(eoFill: false, antialiased: true)
      context.fill(ribbon.body, with: .color(color), style: fillStyle)
      if let startCap = ribbon.startCap {
        context.fill(Path(ellipseIn: startCap), with: .color(color), style: fillStyle)
      }
      if let endCap = ribbon.endCap {
        context.fill(Path(ellipseIn: endCap), with: .color(color), style: fillStyle)
      }

    case .pencil:
      context.drawLayer { layer in
        layer.addFilter(.blur(radius: max(0.4, width * 0.18)))
        layer.stroke(
          path,
          with: .color(color.opacity(0.55)),
          style: StrokeStyle(lineWidth: width * 1.15, lineCap: .round, lineJoin: .round)
        )
      }
      context.stroke(
        path,
        with: .color(color),
        style: StrokeStyle(lineWidth: width * 0.85, lineCap: .round, lineJoin: .round)
      )

    case .highlighter:
      context.blendMode = .multiply
      context.stroke(path, with: .color(color), style: style)
      context.blendMode = .normal

    case .eraser:
      // Punch through prior ink on the same canvas (paper stays in a sibling layer when baking).
      context.blendMode = .destinationOut
      context.stroke(path, with: .color(.black), style: style)
      context.blendMode = .normal
    }
  }

  static func drawDrawing(
    _ drawing: Drawing,
    liveStroke: Stroke? = nil,
    in context: inout GraphicsContext,
    size: CGSize,
    widthScale: CGFloat = 1
  ) {
    for stroke in drawing.strokes {
      draw(stroke, in: &context, size: size, widthScale: widthScale, live: false)
    }
    if let liveStroke {
      draw(liveStroke, in: &context, size: size, widthScale: widthScale, live: true)
    }
  }

  /// Rasterize paper + committed ink once so live drawing doesn’t redraw everything each frame.
  @MainActor
  static func bake(
    _ drawing: Drawing,
    size: CGSize,
    scale: CGFloat,
    paperStyle: PaperStyle = .crosses
  ) -> UIImage? {
    guard size.width > 1, size.height > 1 else { return nil }
    let content = ZStack {
      PaperFill(style: paperStyle)
      Canvas { context, canvasSize in
        drawDrawing(drawing, in: &context, size: canvasSize)
      }
    }
    .frame(width: size.width, height: size.height)

    let renderer = ImageRenderer(content: content)
    renderer.scale = scale
    return renderer.uiImage
  }
}

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
  /// Sheet paper behind the ink (same as the home avatar circle by default).
  var paperStyle: PaperStyle = .crosses
  var onWillCommitStroke: (() -> Void)?

  @Environment(\.displayScale) private var displayScale

  @State private var currentStroke: Stroke?
  @State private var lastSampleTime: TimeInterval?
  @State private var lastSampleLocation: CGPoint?
  @State private var smoothedPenWidth: Double?
  @State private var bakedImage: UIImage?
  @State private var bakedStrokeCount = 0
  @State private var canvasSize: CGSize = .zero

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
    .paperSurface(paperStyle, in: Rectangle())
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
      paperStyle: paperStyle
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

struct DrawingToolbar: View {
  @Binding var tool: DrawingTool
  @Binding var colorHex: String
  @Binding var widthByTool: [DrawingTool: Double]
  var canUndo: Bool = false
  var onUndo: (() -> Void)?

  private var selectedWidth: Double {
    widthByTool[tool] ?? tool.defaultWidth
  }

  var body: some View {
    VStack(spacing: Theme.Spacing.s3) {
      HStack(spacing: Theme.Spacing.s2) {
        ForEach(DrawingTool.allCases, id: \.self) { option in
          Button {
            tool = option
          } label: {
            Image(systemName: option.systemImage)
              .font(.system(size: Theme.Sizing.iconMd, weight: .semibold))
              .foregroundStyle(tool == option ? Theme.Background.primary : Theme.Text.secondary)
              .frame(width: Theme.Sizing.touchTarget, height: Theme.Sizing.touchTarget)
              .background(tool == option ? Theme.Text.primary : Theme.Background.tertiary)
              .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(option.displayName)
        }

        Spacer(minLength: Theme.Spacing.s1)

        Button {
          onUndo?()
        } label: {
          Image(systemName: "arrow.uturn.backward")
            .font(.system(size: Theme.Sizing.iconMd, weight: .semibold))
            .foregroundStyle(canUndo ? Theme.Text.secondary : Theme.Text.placeholder)
            .frame(width: Theme.Sizing.touchTarget, height: Theme.Sizing.touchTarget)
            .background(canUndo ? Theme.Background.tertiary : Theme.Background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canUndo)
        .accessibilityLabel("Undo")
      }

      HStack(spacing: Theme.Spacing.s2) {
        ForEach(tool.availableWidths, id: \.self) { width in
          Button {
            widthByTool[tool] = width
          } label: {
            ZStack {
              RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Background.tertiary)
              RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(
                  selectedWidth == width ? Theme.Stroke.emphasis : Color.clear,
                  lineWidth: Theme.Borders.thick
                )
              sizePreview(for: width)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Sizing.touchTarget)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Nib \(Int(width))")
        }
      }

      if !tool.isEraser {
        HStack(spacing: 0) {
          ForEach(DrawingPalette.hexes, id: \.self) { hex in
            Button {
              colorHex = hex
            } label: {
              Circle()
                .fill(Color(drawingHex: hex))
                .padding(5)
                .overlay {
                  if colorHex == hex {
                    Circle()
                      .strokeBorder(Theme.Stroke.emphasis, lineWidth: Theme.Borders.heavy)
                      .padding(2)
                  }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Color \(hex)")
          }
        }
        .padding(.horizontal, Theme.Spacing.s1)
        .padding(.vertical, Theme.Spacing.s1 + 2)
        .background(Theme.Background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
      }
    }
  }

  @ViewBuilder
  private func sizePreview(for width: Double) -> some View {
    let fill = tool.isEraser
      ? Theme.Text.placeholder
      : Color(drawingHex: colorHex).opacity(tool.opacity)
    // Scale preview dots so the three nibs stay visually distinct at larger widths.
    let previewScale = 0.45
    Capsule()
      .fill(fill)
      .frame(
        width: tool.usesFlatTip
          ? min(28, max(10, width * 0.45))
          : min(26, max(6, width * previewScale * 1.15)),
        height: tool.usesFlatTip
          ? min(20, max(6, width * 0.28))
          : min(26, max(5, width * previewScale))
      )
  }
}

struct DrawingView: View {
  @EnvironmentObject private var session: GameSession
  @State private var drawing = Drawing.empty
  @State private var undoStack = DrawingUndoStack()
  @State private var tool: DrawingTool = .pen
  @State private var colorHex = DrawingPalette.defaultHex
  @State private var widthByTool: [DrawingTool: Double] = Dictionary(
    uniqueKeysWithValues: DrawingTool.allCases.map { ($0, $0.defaultWidth) }
  )

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

    VStack(spacing: Theme.Spacing.s3) {
      HStack(alignment: .firstTextBaseline) {
        Text("Draw")
          .themeText(.heading)
          .foregroundStyle(Theme.Text.primary)
        Spacer()
        PhaseCountdown(endsAt: state?.phaseEndsAt)
      }
      .pageHorizontalPadding()

      Text(prompt)
        .themeText(.subheading)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.Accent.default)

      DrawingCanvas(
        drawing: $drawing,
        tool: tool,
        colorHex: colorHex,
        lineWidth: widthByTool[tool] ?? tool.defaultWidth,
        onWillCommitStroke: { undoStack.registerStrokeAdded() }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .pageHorizontalPadding()

      DrawingToolbar(
        tool: $tool,
        colorHex: $colorHex,
        widthByTool: $widthByTool,
        canUndo: undoStack.canUndo,
        onUndo: { undoStack.undo(drawing: &drawing) }
      )
      .pageHorizontalPadding()

      HStack {
        Button("Clear") {
          undoStack.registerClear(before: drawing)
          drawing = .empty
        }
        .themeText(.label)
        .foregroundStyle(Theme.Text.secondary)
        .disabled(drawing.isEmpty)
        Spacer()
        Button(DoodleLabel.bracketed("Done")) {
          session.submitDrawing(drawing)
          drawing = .empty
          undoStack.reset()
        }
        .doodleButton(.primary)
        .frame(width: 140)
        .disabled(drawing.isEmpty || (state?.submittedPlayerIds.contains(session.localPlayerId) ?? false))
      }
      .pageHorizontalPadding()
      .padding(.bottom, Theme.Spacing.s3)
    }
    .padding(.top, Theme.Spacing.s4)
    .paperBackground(.plain)
    .pageMargins()
    .task(id: state?.phaseEndsAt) {
      await autoSubmitWhenTimerExpires(endsAt: state?.phaseEndsAt)
    }
  }

  /// Submit whatever is on the canvas when time runs out so work isn’t lost to expireTurn.
  private func autoSubmitWhenTimerExpires(endsAt: Date?) async {
    guard let endsAt else { return }
    let delay = endsAt.timeIntervalSinceNow
    if delay > 0 {
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    guard !Task.isCancelled else { return }
    guard let state = session.state,
          state.phase == .drawing,
          !state.submittedPlayerIds.contains(session.localPlayerId),
          !drawing.isEmpty else { return }
    session.submitDrawing(drawing)
    drawing = .empty
    undoStack.reset()
  }
}
