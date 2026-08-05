import SwiftUI

struct AppSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage(PaperStyle.storageKey) private var paperStyleRaw = PaperStyle.plain.rawValue
  @AppStorage(RevealStyle.storageKey) private var revealStyleRaw = RevealStyle.fade.rawValue

  private var selectedStyle: PaperStyle {
    PaperStyle(rawValue: paperStyleRaw) ?? .plain
  }

  private var revealStyle: Binding<RevealStyle> {
    Binding(
      get: { RevealStyle(rawValue: revealStyleRaw) ?? .fade },
      set: { revealStyleRaw = $0.rawValue }
    )
  }

  private let columns = [
    GridItem(.flexible(), spacing: Theme.Spacing.s3),
    GridItem(.flexible(), spacing: Theme.Spacing.s3),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
          Text("Paper")
            .themeText(.overline)
            .foregroundStyle(Theme.Text.secondary)

          Text("Used for drawing canvases and sheets — like the home avatar circle.")
            .themeText(.caption)
            .foregroundStyle(Theme.Text.tertiary)

          LazyVGrid(columns: columns, spacing: Theme.Spacing.s3) {
            ForEach(PaperStyle.allCases) { style in
              paperOption(style)
            }
          }

          Text("Reveal")
            .themeText(.overline)
            .foregroundStyle(Theme.Text.secondary)
            .padding(.top, Theme.Spacing.s3)

          Text("How each drawing arrives during the reveal — finished, or replayed stroke by stroke.")
            .themeText(.caption)
            .foregroundStyle(Theme.Text.tertiary)

          DoodleSegmentedControl(
            options: RevealStyle.allCases,
            selection: revealStyle,
            title: \.displayName
          )
        }
        .pageHorizontalPadding()
        .padding(.top, Theme.Spacing.s4)
        .padding(.bottom, Theme.Spacing.s7)
      }
      .paperBackground()
      .pageMargins()
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .themeText(.label)
            .foregroundStyle(Theme.Accent.default)
        }
      }
    }
  }

  private func paperOption(_ style: PaperStyle) -> some View {
    let isSelected = style == selectedStyle
    return Button {
      paperStyleRaw = style.rawValue
    } label: {
      VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
        PaperFill(style: style)
          .frame(maxWidth: .infinity)
          .frame(height: 96)
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
              .strokeBorder(
                isSelected ? Theme.Stroke.emphasis : Theme.Stroke.subtle,
                lineWidth: isSelected ? Theme.Borders.heavy : Theme.Borders.thin
              )
          }

        Text(style.displayName)
          .themeText(.labelSmall)
          .foregroundStyle(isSelected ? Theme.Text.primary : Theme.Text.secondary)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(style.displayName)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
