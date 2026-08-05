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
    widthScale: CGFloat = 1,
    progress: Double = 1
  ) {
    if progress < 1 {
      drawPartial(drawing, in: &context, size: size, widthScale: widthScale, progress: progress)
    } else {
      for stroke in drawing.strokes {
        draw(stroke, in: &context, size: size, widthScale: widthScale, live: false)
      }
    }
    if let liveStroke {
      draw(liveStroke, in: &context, size: size, widthScale: widthScale, live: true)
    }
  }

  /// Replays strokes in the order they were made, up to `progress` (0…1).
  private static func drawPartial(
    _ drawing: Drawing,
    in context: inout GraphicsContext,
    size: CGSize,
    widthScale: CGFloat,
    progress: Double
  ) {
    let total = sampleCount(of: drawing)
    guard total > 0 else { return }

    var budget = Int((Double(total) * min(max(progress, 0), 1)).rounded())
    for stroke in drawing.strokes {
      guard budget > 0 else { return }
      if budget >= stroke.points.count {
        budget -= stroke.points.count
        draw(stroke, in: &context, size: size, widthScale: widthScale, live: false)
      } else {
        var partial = stroke
        partial.points = Array(stroke.points.prefix(budget))
        budget = 0
        // `live` matches how an in-flight stroke tapers while the finger is still down.
        draw(partial, in: &context, size: size, widthScale: widthScale, live: true)
      }
    }
  }

  /// Points are sampled as the finger moves, so a point budget paces a replay
  /// close to the speed the drawing was made at.
  static func sampleCount(of drawing: Drawing) -> Int {
    drawing.strokes.reduce(0) { $0 + $1.points.count }
  }

  /// Replay length for `drawing`, clamped so a scribble still reads and an epic doesn't stall the reveal.
  static func replayDuration(for drawing: Drawing) -> Double {
    min(2.6, max(0.45, Double(sampleCount(of: drawing)) / 260))
  }

  /// Rasterize paper + committed ink once so live drawing doesn’t redraw everything each frame.
  @MainActor
  static func bake(
    _ drawing: Drawing,
    size: CGSize,
    scale: CGFloat,
    paperStyle: PaperStyle = .plain
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
