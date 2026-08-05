import SwiftUI

/// Title + `[ DONE ]` in a 40pt band between horizontal rails (Figma sheet header).
struct DoodleSheetHeader: View {
  let title: String
  let onDone: () -> Void

  var body: some View {
    HStack(spacing: Theme.Spacing.s2) {
      Text(title)
        .themeText(.body)
        .foregroundStyle(Theme.Text.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)

      Button(action: onDone) {
        Text(DoodleLabel.bracketed("Done"))
          .doodlePrimarySaveLabel(isEnabled: true)
      }
      .buttonStyle(.plain)
    }
    .pageHorizontalPadding()
    .frame(height: Theme.Sizing.inputHeight)
  }
}
