import SwiftUI

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
