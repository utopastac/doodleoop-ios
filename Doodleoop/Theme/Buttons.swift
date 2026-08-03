import SwiftUI

enum DoodleButtonKind {
  /// Ink fill, paper-white label — primary actions (`[ CREATE GAME ]`).
  case primary
  /// Beige fill, ink label — secondary actions (`[ JOIN GAME ]`).
  case secondary
  /// White fill, ink label — tertiary / quiet actions (`[ THE RULES ]`).
  case tertiary
  /// Biro fill — accent emphasis when needed.
  case accent

  var background: Color {
    switch self {
    case .primary: Theme.Ink.deep
    case .secondary: Theme.Paper.beige
    case .tertiary: Theme.Paper.white
    case .accent: Theme.Biro.medium
    }
  }

  var foreground: Color {
    switch self {
    case .primary, .accent: Theme.Paper.white
    case .secondary, .tertiary: Theme.Ink.deep
    }
  }

  var height: CGFloat {
    switch self {
    case .tertiary: Theme.Sizing.inputHeight
    default: Theme.Spacing.s9 // 48 — home primary row
    }
  }

  var horizontalPadding: CGFloat {
    switch self {
    case .tertiary: Theme.Spacing.s3
    case .secondary: Theme.Spacing.s4
    default: Theme.Spacing.s5
    }
  }
}

struct DoodleButtonStyle: ButtonStyle {
  var kind: DoodleButtonKind = .primary
  /// When true, wraps the label as `[ TITLE ]` (design convention).
  var brackets: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .themeText(.button)
      .foregroundStyle(kind.foreground.opacity(configuration.isPressed ? 0.85 : 1))
      .padding(.horizontal, kind.horizontalPadding)
      .frame(maxWidth: .infinity)
      .frame(height: kind.height)
      .background(kind.background.opacity(configuration.isPressed ? 0.88 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 2, style: .circular))
  }
}

extension View {
  func doodleButton(_ kind: DoodleButtonKind = .primary) -> some View {
    buttonStyle(DoodleButtonStyle(kind: kind))
  }
}

/// Formats control copy the way the design system does: `[ LABEL ]`.
enum DoodleLabel {
  static func bracketed(_ title: String) -> String {
    let trimmed = title
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return "[ \(trimmed.uppercased()) ]"
  }
}

// Legacy aliases used across screens — map onto the new kinds.
struct PrimaryButtonStyle: ButtonStyle {
  var color: Color = Theme.Ink.deep

  func makeBody(configuration: Configuration) -> some View {
    let kind: DoodleButtonKind = color == Theme.Biro.medium || color == Theme.Accent.default
      ? .accent
      : .primary
    DoodleButtonStyle(kind: kind).makeBody(configuration: configuration)
  }
}

struct SecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    DoodleButtonStyle(kind: .secondary).makeBody(configuration: configuration)
  }
}

struct TertiaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    DoodleButtonStyle(kind: .tertiary).makeBody(configuration: configuration)
  }
}
