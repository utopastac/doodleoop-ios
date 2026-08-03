import SwiftUI
import UIKit
import CoreText

// MARK: - Paper styles

/// The two paper fills from the design system: plain cream, and white with crosses.
enum PaperStyle: Equatable {
  /// `paper/cream` — page / ruled background.
  case plain
  /// `paper/crosses` — white sheet with plus-mark grid (`size/dot-grid-cell`).
  case crosses

  var fill: Color {
    switch self {
    case .plain: Theme.Paper.cream
    case .crosses: Theme.Paper.white
    }
  }
}

struct PaperFill: View {
  var style: PaperStyle = .plain

  var body: some View {
    ZStack {
      style.fill
      if style == .crosses {
        CrossGridPattern()
      }
    }
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
      case .display: Theme.FontFamily.primaryBold
      case .heading, .subheading, .bodyStrong: Theme.FontFamily.monoBold
      case .body, .label, .labelSmall, .caption, .overline, .button: Theme.FontFamily.monoRegular
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
      let fill = PaperFill(style: style)
      if ignoresSafeArea {
        fill.ignoresSafeArea()
      } else {
        fill
      }
    }
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
  /// Fill behind this view with a paper style (plain cream or crosses).
  func paperBackground(_ style: PaperStyle = .plain, ignoresSafeArea: Bool = true) -> some View {
    modifier(PaperBackgroundModifier(style: style, ignoresSafeArea: ignoresSafeArea))
  }

  /// Always-on left/right grid rails at `Theme.Layout.pageMargin`.
  func pageMargins() -> some View {
    modifier(PageMarginsModifier())
  }

  /// Horizontal content inset matching the page margin rails.
  func pageHorizontalPadding() -> some View {
    padding(.horizontal, Theme.Layout.pageMargin)
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
