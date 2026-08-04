import SwiftUI

enum Theme {

  // MARK: - Primitives

  enum Paper {
    static let white = Color(red: 0.988, green: 0.980, blue: 0.961)
    static let cream = Color(red: 0.961, green: 0.945, blue: 0.910)
    static let beige = Color(red: 0.922, green: 0.898, blue: 0.855)
    static let tan = Color(red: 0.863, green: 0.835, blue: 0.784)
    /// Aged parchment — warmer and a touch duskier than cream.
    static let parchment = Color(red: 0.910, green: 0.855, blue: 0.745)
    /// `paper/broadsheet` — warm newsprint peach.
    static let broadsheet = Color(red: 0.973, green: 0.839, blue: 0.714)
  }

  enum Dot {
    static let light = Color(red: 0.804, green: 0.776, blue: 0.729)
    static let medium = Color(red: 0.706, green: 0.675, blue: 0.627)
  }

  enum Ink {
    static let deep = Color(red: 0.098, green: 0.086, blue: 0.071)
    static let dark = Color(red: 0.176, green: 0.157, blue: 0.137)
    static let medium = Color(red: 0.275, green: 0.247, blue: 0.216)
  }

  enum Pencil {
    static let dark = Color(red: 0.353, green: 0.333, blue: 0.306)
    static let medium = Color(red: 0.510, green: 0.486, blue: 0.451)
    static let light = Color(red: 0.667, green: 0.639, blue: 0.600)
    static let faint = Color(red: 0.765, green: 0.737, blue: 0.698)
  }

  enum Biro {
    static let bold = Color(red: 0.039, green: 0.196, blue: 0.698)
    static let medium = Color(red: 0.157, green: 0.282, blue: 0.725)
    static let light = Color(red: 0.314, green: 0.431, blue: 0.784)
    static let faint = Color(red: 0.549, green: 0.627, blue: 0.863)
  }

  // MARK: - Semantic

  enum Background {
    /// Page chrome — cream ruled paper.
    static let primary = Paper.cream
    static let secondary = Paper.cream
    static let tertiary = Paper.beige
    static let elevated = Paper.tan
    /// Sheet / elevated white paper (also used under crosses and dots).
    static let sheet = Paper.white
    /// `paper/broadsheet` — warm newsprint peach.
    static let broadsheet = Paper.broadsheet
  }

  enum Grid {
    static let dot = Dot.light
    static let dotEmphasis = Dot.medium
  }

  enum Text {
    static let primary = Ink.deep
    static let secondary = Pencil.dark
    static let tertiary = Pencil.medium
    static let placeholder = Pencil.faint
  }

  enum Stroke {
    static let `default` = Pencil.light
    static let subtle = Dot.light
    static let emphasis = Ink.medium
  }

  enum Accent {
    static let `default` = Biro.bold
    static let hover = Biro.medium
    static let subtle = Biro.light
    static let muted = Biro.faint
  }

  enum Interactive {
    static let link = Biro.bold
    static let focus = Biro.medium
  }

  // MARK: - Spacing / sizing / borders / radius

  enum Spacing {
    static let s0: CGFloat = 0
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 32
    static let s8: CGFloat = 40
    static let s9: CGFloat = 48
    static let s10: CGFloat = 64
    static let s11: CGFloat = 80
    static let s12: CGFloat = 96
  }

  /// Page / screen layout metrics.
  enum Layout {
    /// Horizontal inset from screen edge to content and margin rails.
    /// Always 24pt — match Figma page chrome; use for padding and content width.
    static let pageMargin = Spacing.s6
  }

  enum Sizing {
    static let iconSm: CGFloat = 16
    static let iconMd: CGFloat = 20
    static let iconLg: CGFloat = 24
    static let avatarSm: CGFloat = 32
    static let avatarMd: CGFloat = 40
    static let avatarLg: CGFloat = 56
    static let touchTarget: CGFloat = 44
    static let inputHeight: CGFloat = 40
    static let buttonHeight: CGFloat = 36
    static let dotGridCell: CGFloat = 20
    /// Pitch between ruled-paper horizontal lines.
    static let ruleSpacing: CGFloat = 28
    /// Trailing inset so top-row content clears the global leave control.
    static let leaveButtonReserve: CGFloat = inputHeight + Spacing.s2
  }

  enum Borders {
    static let hairline: CGFloat = 0.5
    static let thin: CGFloat = 1
    static let medium: CGFloat = 1.5
    static let thick: CGFloat = 2
    static let heavy: CGFloat = 3
  }

  enum Radius {
    static let none: CGFloat = 0
    /// Figma `radius/sm` — icon buttons, doodle controls.
    static let xs: CGFloat = 2
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 24
    static let full: CGFloat = 9999
  }

  // MARK: - Typography

  enum FontFamily {
    /// PostScript name — Fraunces 72pt Bold.
    static let primaryBold = "Fraunces72pt-Bold"
    /// PostScript name — Space Mono Regular.
    static let monoRegular = "SpaceMono-Regular"
    /// PostScript name — Space Mono Bold.
    static let monoBold = "SpaceMono-Bold"
  }

  enum FontSize {
    static let caption2: CGFloat = 11
    static let caption1: CGFloat = 12
    static let footnote: CGFloat = 13
    static let subheadline: CGFloat = 15
    static let callout: CGFloat = 16
    static let body: CGFloat = 17
    static let title3: CGFloat = 20
    static let title2: CGFloat = 22
    static let title1: CGFloat = 34
    /// Drawing-page timer (`00.45`).
    static let timer: CGFloat = 36
    static let largeTitle: CGFloat = 44
  }

  enum LineHeight {
    static let caption2: CGFloat = 13
    static let caption1: CGFloat = 16
    static let footnote: CGFloat = 18
    static let subheadline: CGFloat = 20
    static let callout: CGFloat = 21
    static let body: CGFloat = 22
    static let title3: CGFloat = 25
    static let title2: CGFloat = 28
    static let title1: CGFloat = 38
    static let timer: CGFloat = 36
    static let largeTitle: CGFloat = 48
  }

  /// Named text styles from the design system.
  enum TextStyle: CaseIterable {
    case display
    /// Fraunces Bold at title-1 — drawing prompt / category.
    case heading
    case subheading
    /// Space Mono Regular timer (`00.45`).
    case timer
    case body
    case bodyStrong
    case label
    case labelSmall
    case caption
    case overline
    case button

    var font: Font {
      switch self {
      case .display:
        .custom(FontFamily.primaryBold, size: FontSize.largeTitle)
      case .heading:
        .custom(FontFamily.primaryBold, size: FontSize.title1)
      case .subheading:
        .custom(FontFamily.monoBold, size: FontSize.title2)
      case .timer:
        .custom(FontFamily.monoRegular, size: FontSize.timer)
      case .body:
        .custom(FontFamily.monoRegular, size: FontSize.body)
      case .bodyStrong:
        .custom(FontFamily.monoBold, size: FontSize.body)
      case .label:
        .custom(FontFamily.monoRegular, size: FontSize.subheadline)
      case .labelSmall:
        .custom(FontFamily.monoRegular, size: FontSize.footnote)
      case .caption:
        .custom(FontFamily.monoRegular, size: FontSize.caption1)
      case .overline:
        .custom(FontFamily.monoRegular, size: FontSize.caption2)
      case .button:
        .custom(FontFamily.monoRegular, size: FontSize.subheadline)
      }
    }

    /// Tracking in points (Figma percent × font size / 100).
    var tracking: CGFloat {
      switch self {
      case .body: FontSize.body * 0.07
      case .button: FontSize.subheadline * 0.05
      default: 0
      }
    }

    var lineHeight: CGFloat {
      switch self {
      case .display: LineHeight.largeTitle
      case .heading: LineHeight.title1
      case .subheading: LineHeight.title2
      case .timer: LineHeight.timer
      case .body, .bodyStrong, .button: LineHeight.body
      case .label: LineHeight.subheadline
      case .labelSmall: LineHeight.footnote
      case .caption: LineHeight.caption1
      case .overline: LineHeight.caption2
      }
    }

    var fontSize: CGFloat {
      switch self {
      case .display: FontSize.largeTitle
      case .heading: FontSize.title1
      case .subheading: FontSize.title2
      case .timer: FontSize.timer
      case .body, .bodyStrong: FontSize.body
      case .label, .button: FontSize.subheadline
      case .labelSmall: FontSize.footnote
      case .caption: FontSize.caption1
      case .overline: FontSize.caption2
      }
    }

    var textCase: SwiftUI.Text.Case? {
      switch self {
      case .body, .button: .uppercase
      default: nil
      }
    }

    /// Extra spacing for pre–iOS 26 `.lineSpacing` (adds on top of `uiFont.lineHeight`).
    /// Zero when the Figma line height is at or below the font's natural metrics.
    var lineSpacing: CGFloat {
      max(0, lineHeight - uiFont.lineHeight)
    }
  }
}

extension View {
  @ViewBuilder
  func themeText(_ style: Theme.TextStyle) -> some View {
    if #available(iOS 26.0, *) {
      // Baseline-to-baseline — matches Figma absolute line height (e.g. display 44/48).
      self
        .font(style.font)
        .tracking(style.tracking)
        .lineHeight(.exact(points: style.lineHeight))
        .textCase(style.textCase)
    } else {
      self
        .font(style.font)
        .tracking(style.tracking)
        .lineSpacing(style.lineSpacing)
        .textCase(style.textCase)
    }
  }
}

extension Color {
  init(drawingHex hex: String) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&value)
    let hasAlpha = cleaned.count == 8
    let a = hasAlpha ? Double((value & 0xFF00_0000) >> 24) / 255 : 1
    let r = Double((value & 0x00FF_0000) >> 16) / 255
    let g = Double((value & 0x0000_FF00) >> 8) / 255
    let b = Double(value & 0x0000_00FF) / 255
    self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
  }
}
