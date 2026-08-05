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

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .themeText(.button)
      .foregroundStyle(kind.foreground.opacity(configuration.isPressed ? 0.85 : 1))
      .padding(.horizontal, kind.horizontalPadding)
      .frame(maxWidth: .infinity)
      .frame(height: kind.height)
      .background(kind.background.opacity(configuration.isPressed ? 0.88 : 1))
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
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

/// Shared ink primary save / done styling — enabled and disabled states.
extension View {
  func doodlePrimarySaveLabel(isEnabled: Bool) -> some View {
    self
      .themeText(.button)
      .foregroundStyle(Theme.Paper.tan.opacity(isEnabled ? 1 : 0.5))
      .padding(.horizontal, Theme.Spacing.s5)
      .frame(height: Theme.Sizing.inputHeight)
      .background(Theme.Ink.deep.opacity(isEnabled ? 1 : 0.35))
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
  }
}

struct DoodlePrimarySaveButton: View {
  let title: String
  var isEnabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(DoodleLabel.bracketed(title))
        .doodlePrimarySaveLabel(isEnabled: isEnabled)
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
  }
}

/// Equal-width segmented control — same language as Create / Join on home:
/// bracketed mono labels, ink selected fill, paper unselected, grid-line gutters.
struct DoodleSegmentedControl<Option: Hashable>: View {
  let options: [Option]
  @Binding var selection: Option
  let title: (Option) -> String

  init(
    options: [Option],
    selection: Binding<Option>,
    title: @escaping (Option) -> String
  ) {
    self.options = options
    self._selection = selection
    self.title = title
  }

  init(
    options: [Option],
    selection: Binding<Option>,
    title keyPath: KeyPath<Option, String>
  ) {
    self.options = options
    self._selection = selection
    self.title = { $0[keyPath: keyPath] }
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(options.enumerated()), id: \.offset) { index, option in
        let isSelected = option == selection
        Button {
          selection = option
        } label: {
          Text(DoodleLabel.bracketed(title(option)))
            .themeText(.button)
            .foregroundStyle(isSelected ? Theme.Paper.white : Theme.Ink.deep)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Sizing.inputHeight)
            .background(isSelected ? Theme.Ink.deep : Theme.Paper.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if index < options.count - 1 {
          GridLine(axis: .vertical)
            .frame(maxHeight: .infinity)
        }
      }
    }
    .frame(height: Theme.Sizing.inputHeight)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular)
        .strokeBorder(Theme.Stroke.subtle, lineWidth: Theme.Borders.thin)
    }
  }
}
