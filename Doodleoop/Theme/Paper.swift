import SwiftUI
import UIKit
import CoreText

// MARK: - Paper styles

/// Paper fills from the design system / appearance settings.
enum PaperStyle: String, CaseIterable, Identifiable, Equatable {
  /// `paper/cream` — page / plain background.
  case plain
  /// `paper/dots` — white sheet with dot grid (`size/dot-grid-cell`).
  case dots
  /// `paper/crosses` — white sheet with plus-mark grid (`size/dot-grid-cell`).
  case crosses
  /// White sheet with horizontal writing rules.
  case ruled
  /// Warm aged parchment with soft grain and mottling.
  case parchment
  /// Photo texture asset (`PaperTexture`).
  case textured
  /// Canvas weave photo asset (`PaperCanvas`).
  case canvas

  static let storageKey = "appearance.paperStyle"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .plain: "Plain"
    case .dots: "Dots"
    case .crosses: "Plus"
    case .ruled: "Rules"
    case .parchment: "Parchment"
    case .textured: "Texture"
    case .canvas: "Canvas"
    }
  }

  var fill: Color {
    switch self {
    case .plain, .textured: Theme.Paper.cream
    case .crosses, .dots, .ruled: Theme.Paper.white
    case .parchment: Theme.Paper.parchment
    case .canvas: Theme.Paper.canvas
    }
  }
}

private struct PaperStyleKey: EnvironmentKey {
  static let defaultValue: PaperStyle = .plain
}

extension EnvironmentValues {
  /// Preferred paper for drawing surfaces (canvases, avatar sheets) — not page chrome.
  var paperStyle: PaperStyle {
    get { self[PaperStyleKey.self] }
    set { self[PaperStyleKey.self] = newValue }
  }
}

struct PaperFill: View {
  /// When set, ignores the environment preference (previews / explicit swatches).
  private var explicitStyle: PaperStyle?
  @Environment(\.paperStyle) private var preferredStyle

  init(style: PaperStyle? = nil) {
    self.explicitStyle = style
  }

  private var style: PaperStyle { explicitStyle ?? preferredStyle }

  var body: some View {
    ZStack {
      style.fill
      switch style {
      case .plain:
        EmptyView()
      case .crosses:
        CrossGridPattern()
      case .dots:
        DotGridPattern()
      case .ruled:
        HorizontalRulesPattern()
      case .parchment:
        ParchmentTexture()
      case .textured:
        PaperAssetImage(name: "PaperTexture")
      case .canvas:
        PaperAssetImage(name: "PaperCanvas")
      }
    }
  }
}

/// Full-bleed paper photo from the asset catalog.
private struct PaperAssetImage: View {
  var name: String

  var body: some View {
    GeometryReader { geo in
      Image(name)
        .resizable()
        .scaledToFill()
        .frame(width: geo.size.width, height: geo.size.height)
        .clipped()
    }
    .allowsHitTesting(false)
  }
}

/// Repeating `+` marks on a `size/dot-grid-cell` pitch.
struct CrossGridPattern: View {
  var cell: CGFloat = Theme.Sizing.dotGridCell
  var color: Color = Theme.Grid.dot
  /// Half-length of each cross arm.
  var arm: CGFloat = 3

  var body: some View {
    Canvas { context, size in
      var path = Path()
      var y: CGFloat = cell / 2
      while y < size.height + cell {
        var x: CGFloat = cell / 2
        while x < size.width + cell {
          path.move(to: CGPoint(x: x - arm, y: y))
          path.addLine(to: CGPoint(x: x + arm, y: y))
          path.move(to: CGPoint(x: x, y: y - arm))
          path.addLine(to: CGPoint(x: x, y: y + arm))
          x += cell
        }
        y += cell
      }
      context.stroke(path, with: .color(color), lineWidth: Theme.Borders.thin)
    }
    .allowsHitTesting(false)
  }
}

/// Repeating dots on a `size/dot-grid-cell` pitch (`paper/dots`).
struct DotGridPattern: View {
  var cell: CGFloat = Theme.Sizing.dotGridCell
  var color: Color = Theme.Grid.dot
  /// Dot diameter.
  var diameter: CGFloat = 2

  var body: some View {
    Canvas { context, size in
      let radius = diameter / 2
      var y: CGFloat = cell / 2
      while y < size.height + cell {
        var x: CGFloat = cell / 2
        while x < size.width + cell {
          let rect = CGRect(x: x - radius, y: y - radius, width: diameter, height: diameter)
          context.fill(Path(ellipseIn: rect), with: .color(color))
          x += cell
        }
        y += cell
      }
    }
    .allowsHitTesting(false)
  }
}

/// Horizontal notebook rules on a `size/rule-spacing` pitch.
struct HorizontalRulesPattern: View {
  var spacing: CGFloat = Theme.Sizing.ruleSpacing
  var color: Color = Theme.Grid.dot
  /// Optional left margin rule (classic notebook gutter).
  var marginRule: Color? = Theme.Accent.muted.opacity(0.55)
  var marginX: CGFloat = Theme.Spacing.s7

  var body: some View {
    Canvas { context, size in
      var rules = Path()
      var y: CGFloat = spacing
      while y < size.height {
        rules.move(to: CGPoint(x: 0, y: y))
        rules.addLine(to: CGPoint(x: size.width, y: y))
        y += spacing
      }
      context.stroke(rules, with: .color(color), lineWidth: Theme.Borders.hairline)

      if let marginRule {
        var margin = Path()
        margin.move(to: CGPoint(x: marginX, y: 0))
        margin.addLine(to: CGPoint(x: marginX, y: size.height))
        context.stroke(margin, with: .color(marginRule), lineWidth: Theme.Borders.thin)
      }
    }
    .allowsHitTesting(false)
  }
}

/// Soft grain, mottling, and edge wear for aged parchment.
struct ParchmentTexture: View {
  var body: some View {
    GeometryReader { geo in
      let size = geo.size
      let vignetteRadius = hypot(size.width, size.height) * 0.55

      ZStack {
        // Warm directional wash — sun-faded center, duskier corners.
        LinearGradient(
          colors: [
            Theme.Paper.cream.opacity(0.55),
            Theme.Paper.tan.opacity(0.35),
            Theme.Paper.beige.opacity(0.45),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        RadialGradient(
          colors: [
            Color.clear,
            Theme.Ink.medium.opacity(0.08),
          ],
          center: .center,
          startRadius: min(size.width, size.height) * 0.15,
          endRadius: vignetteRadius
        )

        Canvas { context, canvasSize in
          // Soft age blotches.
          let blotches: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.18, 0.22, 0.42, 0.045),
            (0.72, 0.18, 0.36, 0.04),
            (0.55, 0.58, 0.55, 0.05),
            (0.28, 0.78, 0.38, 0.035),
            (0.82, 0.72, 0.32, 0.04),
            (0.12, 0.55, 0.28, 0.03),
          ]
          for (nx, ny, scale, opacity) in blotches {
            let w = canvasSize.width * scale
            let h = canvasSize.height * scale * 0.7
            let rect = CGRect(
              x: canvasSize.width * nx - w / 2,
              y: canvasSize.height * ny - h / 2,
              width: w,
              height: h
            )
            context.fill(
              Path(ellipseIn: rect),
              with: .color(Theme.Paper.tan.opacity(opacity))
            )
          }

          // Fine fiber grain — deterministic so it doesn't shimmer.
          let step: CGFloat = 5
          var y: CGFloat = 0
          while y < canvasSize.height {
            var x: CGFloat = 0
            while x < canvasSize.width {
              let n = parchmentNoise(x: x, y: y)
              if n > 0.72 {
                let alpha = (n - 0.72) * 0.35
                let speck = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                context.fill(
                  Path(ellipseIn: speck),
                  with: .color(Theme.Dot.medium.opacity(alpha))
                )
              }
              x += step
            }
            y += step
          }
        }
      }
    }
    .allowsHitTesting(false)
  }

  /// Stable 0…1 noise from position.
  private func parchmentNoise(x: CGFloat, y: CGFloat) -> CGFloat {
    let ix = Int(x * 12.9898 + y * 78.233)
    var n = UInt32(bitPattern: Int32(truncatingIfNeeded: ix &* 1_597_334_677))
    n ^= n &<< 13
    n ^= n &>> 17
    n ^= n &<< 5
    return CGFloat(n % 10_000) / 10_000
  }
}

// MARK: - Page / layout grid lines

/// Structural layout lines (black @ 10%), matching Figma `grid-line`.
enum ThemeGrid {
  static let line = Theme.Ink.deep.opacity(0.1)
  /// Alias of `Theme.Layout.pageMargin` — left/right rail inset.
  static let margin = Theme.Layout.pageMargin
}

struct GridLine: View {
  enum Axis { case horizontal, vertical }

  var axis: Axis
  var color: Color = ThemeGrid.line
  var lineWidth: CGFloat = Theme.Borders.thin

  var body: some View {
    Rectangle()
      .fill(color)
      .frame(
        width: axis == .vertical ? lineWidth : nil,
        height: axis == .horizontal ? lineWidth : nil
      )
      .frame(maxWidth: axis == .horizontal ? .infinity : nil)
      .allowsHitTesting(false)
  }
}

/// Page chrome rails: left/right at `Theme.Layout.pageMargin` (full bleed through
/// safe areas), plus horizontals framing the safe-area top and bottom.
struct PageMarginRails: View {
  var body: some View {
    ZStack {
      // Vertical rails — extend into status bar / home indicator.
      HStack(spacing: 0) {
        Color.clear.frame(width: Theme.Layout.pageMargin)
        Rectangle()
          .fill(ThemeGrid.line)
          .frame(width: Theme.Borders.thin)
          .frame(maxHeight: .infinity)
        Spacer(minLength: 0)
        Rectangle()
          .fill(ThemeGrid.line)
          .frame(width: Theme.Borders.thin)
          .frame(maxHeight: .infinity)
        Color.clear.frame(width: Theme.Layout.pageMargin)
      }
      .ignoresSafeArea()

      // Horizontal rails — sit on the safe-area edges only.
      VStack(spacing: 0) {
        GridLine(axis: .horizontal)
        Spacer(minLength: 0)
        GridLine(axis: .horizontal)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(false)
  }
}

/// How a `gridBand` sizes itself vertically.
enum GridBandCrop: Equatable {
  /// Use the view’s normal SwiftUI layout bounds (includes font leading).
  case bounds
  /// Pull horizontal rails in to the ink/glyph bounds of `text` in `style`.
  case glyphs(text: String, style: Theme.TextStyle)
}

/// Core Text ink metrics for cropping layout chrome to painted glyphs.
enum GlyphMetrics {
  /// Top/bottom padding to remove so a text view’s frame matches ink bounds.
  static func verticalTrim(text: String, style: Theme.TextStyle) -> (top: CGFloat, bottom: CGFloat) {
    let display = style.textCase == .uppercase ? text.uppercased() : text
    let font = style.uiFont
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .kern: style.tracking,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: display, attributes: attrs))

    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

    // Image bounds: origin at baseline, +Y up (Core Text).
    let ink = CTLineGetImageBounds(line, nil)
    guard !ink.isNull, !ink.isInfinite, ink.height > 0 else {
      // Fallback: cap-height for uppercase UI labels.
      let cap = font.capHeight
      let layout = ascent + descent
      let slack = max(0, layout - cap)
      return (slack / 2, slack / 2)
    }

    let top = max(0, ascent - ink.maxY)
    let bottom = max(0, descent + ink.minY)
    return (top, bottom)
  }

  /// Tight ink height for `text` in `style`.
  static func inkHeight(text: String, style: Theme.TextStyle) -> CGFloat {
    let trim = verticalTrim(text: text, style: style)
    return max(0, style.uiFont.lineHeight - trim.top - trim.bottom)
  }
}

extension Theme.TextStyle {
  var uiFont: UIFont {
    let name: String = {
      switch self {
      case .display, .heading: Theme.FontFamily.primaryBold
      case .subheading, .bodyStrong: Theme.FontFamily.monoBold
      case .body, .timer, .label, .labelSmall, .caption, .overline, .button: Theme.FontFamily.monoRegular
      }
    }()
    return UIFont(name: name, size: fontSize) ?? .systemFont(ofSize: fontSize)
  }
}

/// Wraps a content group with horizontal grid lines above and below.
struct GridBand<Content: View>: View {
  var spacing: CGFloat = 0
  var crop: GridBandCrop = .bounds
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(spacing: spacing) {
      GridLine(axis: .horizontal)
      croppedContent
      GridLine(axis: .horizontal)
    }
  }

  @ViewBuilder
  private var croppedContent: some View {
    switch crop {
    case .bounds:
      content()
    case .glyphs(let text, let style):
      let trim = GlyphMetrics.verticalTrim(text: text, style: style)
      content()
        .padding(.top, -trim.top)
        .padding(.bottom, -trim.bottom)
    }
  }
}

// MARK: - View modifiers

private struct PaperBackgroundModifier: ViewModifier {
  var style: PaperStyle
  var ignoresSafeArea: Bool

  func body(content: Content) -> some View {
    content.background {
      // Always explicit so page chrome never picks up the drawing-paper preference.
      let fill = PaperFill(style: style)
      if ignoresSafeArea {
        fill.ignoresSafeArea()
      } else {
        fill
      }
    }
  }
}

private struct PaperSurfaceModifier<S: Shape>: ViewModifier {
  var style: PaperStyle?
  var shape: S
  @Environment(\.paperStyle) private var preferredStyle

  func body(content: Content) -> some View {
    content
      .background { PaperFill(style: style ?? preferredStyle) }
      .clipShape(shape)
  }
}

private struct PageMarginsModifier: ViewModifier {
  func body(content: Content) -> some View {
    content.overlay { PageMarginRails() }
  }
}

private struct GridBandModifier: ViewModifier {
  var spacing: CGFloat
  var crop: GridBandCrop

  func body(content: Content) -> some View {
    GridBand(spacing: spacing, crop: crop) { content }
  }
}

extension View {
  /// Page chrome fill — always cream/plain by default; not the drawing-paper preference.
  func paperBackground(_ style: PaperStyle = .plain, ignoresSafeArea: Bool = true) -> some View {
    modifier(PaperBackgroundModifier(style: style, ignoresSafeArea: ignoresSafeArea))
  }

  /// Drawing-surface paper (canvases, avatar circles) — uses the preferred style when omitted.
  func paperSurface<S: Shape>(_ style: PaperStyle? = nil, in shape: S) -> some View {
    modifier(PaperSurfaceModifier(style: style, shape: shape))
  }

  /// Thin edge matching page `grid-line` — square drawing canvases.
  @ViewBuilder
  func drawingCanvasBorder(_ isEnabled: Bool = true) -> some View {
    if isEnabled {
      overlay {
        Rectangle()
          .strokeBorder(ThemeGrid.line, lineWidth: Theme.Borders.thin)
      }
    } else {
      self
    }
  }

  /// Always-on left/right grid rails at `Theme.Layout.pageMargin`.
  func pageMargins() -> some View {
    modifier(PageMarginsModifier())
  }

  /// Horizontal content inset matching the page margin rails.
  func pageHorizontalPadding() -> some View {
    padding(.horizontal, Theme.Layout.pageMargin)
  }

  /// Top inset for a header bar so it clears a sheet's rounded top edge.
  /// Every sheet with its own header bar needs this.
  func sheetHeaderInset() -> some View {
    padding(.top, Theme.Layout.sheetHeaderInset)
  }

  /// Surround this group with horizontal grid lines at its top and bottom.
  /// - Parameters:
  ///   - spacing: Extra gap between rails and content.
  ///   - crop: `.bounds` uses layout size; `.glyphs(text:style:)` hugs painted letterforms.
  func gridBand(spacing: CGFloat = 0, crop: GridBandCrop = .bounds) -> some View {
    modifier(GridBandModifier(spacing: spacing, crop: crop))
  }

  /// Back-compat: margins only (prefer `pageMargins()` + `gridBand()`).
  func pageGrid(
    margins: Bool = true,
    horizontalOffsets: [CGFloat] = [],
    horizontalFractions: [CGFloat] = [],
    verticalOffsets: [CGFloat] = []
  ) -> some View {
    // Offsets ignored — surround groups with `.gridBand()` instead.
    _ = horizontalOffsets
    _ = horizontalFractions
    _ = verticalOffsets
    _ = margins
    return pageMargins()
  }
}
