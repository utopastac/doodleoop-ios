import SwiftUI

/// Instagram-style peek zoom: pinch to magnify in place, let go and it springs back.
///
/// Everything lives in `@GestureState`, which SwiftUI resets on its own when the
/// fingers lift — so the zoom has no state that can be left stuck.
struct ZoomableDrawingView: View {
  let drawing: Drawing
  var progress: Double = 1
  var scalesStrokeWidth: Bool = false
  var showsPaper: Bool = true

  private static let springBack = Transaction(animation: Theme.Motion.reveal)

  @Environment(DrawingZoomLayer.self) private var layer: DrawingZoomLayer?

  @GestureState(resetTransaction: springBack) private var zoom: CGFloat = 1
  @GestureState(resetTransaction: springBack) private var pan = PanState()
  /// Held in `@State` rather than `@GestureState` so the drawing shrinks back toward
  /// the point it grew from instead of sliding to the centre as it springs back.
  @State private var anchor: UnitPoint = .center
  /// A box, not `@State`: the frame changes on every scroll tick and re-rendering
  /// the canvas that often would be wasteful.
  @State private var frame = FrameBox()

  /// Pan is measured from the moment the pinch starts, not from touch-down, so a
  /// pinch that follows a scroll drag doesn't jump by the distance already swiped.
  private struct PanState {
    var origin: CGSize = .zero
    var offset: CGSize = .zero
  }

  private final class FrameBox {
    var value: CGRect = .zero
  }

  private struct Transform: Equatable {
    var scale: CGFloat
    var offset: CGSize
    var anchor: UnitPoint
  }

  private var transform: Transform {
    Transform(scale: zoom, offset: pan.offset, anchor: anchor)
  }

  var body: some View {
    ReadOnlyDrawingView(
      drawing: drawing,
      progress: progress,
      scalesStrokeWidth: scalesStrokeWidth,
      showsPaper: showsPaper
    )
    .scaleEffect(zoom, anchor: anchor)
    .offset(pan.offset)
    // Fallback ordering for screens with no zoom layer of their own.
    .zIndex(zoom > 1 ? 1 : 0)
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.value = $0 }
    .onChange(of: transform) { previous, current in
      publish(previous: previous, current: current)
    }
    .simultaneousGesture(peekZoom)
  }

  /// Mirrors the pinch into the screen's zoom layer, which draws it above everything else.
  private func publish(previous: Transform, current: Transform) {
    guard let layer else { return }
    if current.scale > 1 {
      layer.peek = DrawingZoomLayer.Peek(
        drawing: drawing,
        progress: progress,
        frame: frame.value,
        scale: current.scale,
        anchor: current.anchor,
        offset: current.offset,
        scalesStrokeWidth: scalesStrokeWidth,
        showsPaper: showsPaper
      )
    } else if previous.scale > 1 {
      // The gesture is over: settle the floating copy the same way the inline one settles.
      withAnimation(Theme.Motion.reveal) {
        layer.peek?.scale = 1
        layer.peek?.offset = .zero
      } completion: {
        layer.peek = nil
      }
    }
  }

  private var peekZoom: some Gesture {
    MagnifyGesture()
      .updating($zoom) { value, state, _ in
        state = max(1, value.magnification)
      }
      // `startAnchor` is where the fingers landed, so the pinched spot stays put.
      .onChanged { value in
        anchor = value.startAnchor
      }
      .simultaneously(
        with: DragGesture(minimumDistance: 0)
          .updating($pan) { value, state, _ in
            // Moves with the fingers only once a pinch is under way, so a plain
            // swipe still scrolls the page this sits in.
            guard zoom > 1 else {
              state.origin = value.translation
              state.offset = .zero
              return
            }
            state.offset = CGSize(
              width: value.translation.width - state.origin.width,
              height: value.translation.height - state.origin.height
            )
          }
      )
  }
}

// MARK: - Floating zoom layer

/// Hosts the magnified copy of whichever drawing is being pinched, so a peek zoom
/// isn't clipped by the scroll view the drawing lives in.
@MainActor
@Observable
final class DrawingZoomLayer {
  struct Peek: Equatable {
    var drawing: Drawing
    var progress: Double
    /// Where the drawing sits on screen, in global coordinates.
    var frame: CGRect
    var scale: CGFloat
    var anchor: UnitPoint
    var offset: CGSize
    var scalesStrokeWidth: Bool
    var showsPaper: Bool

    /// Fades the screen down as the pinch opens up, topping out well short of black.
    var dimOpacity: Double {
      let ramp = min(1, max(0, (Double(scale) - 1) / 1.5))
      return ramp * 0.5
    }
  }

  var peek: Peek?
}

private struct DrawingZoomLayerModifier: ViewModifier {
  @State private var layer = DrawingZoomLayer()
  @State private var origin: CGPoint = .zero

  func body(content: Content) -> some View {
    content
      .environment(layer)
      .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
      .overlay {
        if let peek = layer.peek {
          ZStack {
            Theme.Ink.deep
              .opacity(peek.dimOpacity)
              .ignoresSafeArea()

            ReadOnlyDrawingView(
              drawing: peek.drawing,
              progress: peek.progress,
              scalesStrokeWidth: peek.scalesStrokeWidth,
              showsPaper: peek.showsPaper
            )
            .frame(width: peek.frame.width, height: peek.frame.height)
            .scaleEffect(peek.scale, anchor: peek.anchor)
            .offset(peek.offset)
            .position(x: peek.frame.midX - origin.x, y: peek.frame.midY - origin.y)
          }
          .allowsHitTesting(false)
        }
      }
  }
}

extension View {
  /// Lets any `ZoomableDrawingView` on this screen draw its pinch above everything else.
  /// Apply once per screen root — including sheets, which present outside their parent.
  func drawingZoomLayer() -> some View {
    modifier(DrawingZoomLayerModifier())
  }
}
