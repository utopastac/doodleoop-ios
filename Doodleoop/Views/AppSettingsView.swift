import SwiftUI

struct AppSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage(PaperStyle.storageKey) private var paperStyleRaw = PaperStyle.plain.rawValue
  @AppStorage(RevealStyle.storageKey) private var revealStyleRaw = RevealStyle.fade.rawValue

  /// Figma `paper style` swatch — capsule sheet over its label.
  private let swatchSize = CGSize(width: 88, height: 140)

  private var selectedStyle: PaperStyle {
    PaperStyle(rawValue: paperStyleRaw) ?? .plain
  }

  private var revealStyle: Binding<RevealStyle> {
    Binding(
      get: { RevealStyle(rawValue: revealStyleRaw) ?? .fade },
      set: { revealStyleRaw = $0.rawValue }
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      DoodleSheetHeader(title: "Settings", onDone: { dismiss() })
        .gridBand()
        .sheetHeaderInset()

      ScrollView {
        VStack(spacing: 0) {
          section("Paper style") {
            paperStyles
          }

          GridLine(axis: .horizontal)

          section("Reveal style") {
            DoodleSegmentedControl(
              options: RevealStyle.allCases,
              selection: revealStyle,
              title: \.displayName
            )
            .pageHorizontalPadding()
          }

          GridLine(axis: .horizontal)
        }
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperBackground()
    .pageMargins()
  }

  private func section<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
      Text(title)
        .themeText(.body)
        .foregroundStyle(Theme.Text.primary)
        .frame(height: Theme.Sizing.inputHeight, alignment: .leading)
        .pageHorizontalPadding()
        .accessibilityAddTraits(.isHeader)

      content()
    }
    .padding(.top, Theme.Spacing.s6)
    .padding(.bottom, Theme.Spacing.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The swatch row runs past the trailing rail, so it scrolls sideways.
  private var paperStyles: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: Theme.Spacing.s4) {
          ForEach(PaperStyle.allCases) { style in
            paperOption(style)
              .id(style)
          }
        }
      }
      .contentMargins(.horizontal, Theme.Layout.pageMargin, for: .scrollContent)
      .onAppear {
        proxy.scrollTo(selectedStyle, anchor: .center)
      }
    }
  }

  private func paperOption(_ style: PaperStyle) -> some View {
    let isSelected = style == selectedStyle
    return Button {
      paperStyleRaw = style.rawValue
    } label: {
      VStack(spacing: Theme.Spacing.s2) {
        PaperFill(style: style)
          .frame(width: swatchSize.width, height: swatchSize.height)
          .clipShape(Capsule(style: .continuous))
          .overlay {
            // Plain paper is the same cream as the page, so unselected swatches
            // still need a hairline to read as a swatch.
            Capsule(style: .continuous)
              .strokeBorder(
                isSelected ? Theme.Ink.deep : Theme.Stroke.subtle,
                lineWidth: isSelected ? Theme.Borders.heavy : Theme.Borders.thin
              )
          }

        Text(style.displayName)
          .textCase(.uppercase)
          .themeText(.labelSmall)
          .foregroundStyle(Theme.Text.primary)
          .tracking(Theme.FontSize.footnote * 0.07)
          .frame(width: swatchSize.width)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(style.displayName)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
