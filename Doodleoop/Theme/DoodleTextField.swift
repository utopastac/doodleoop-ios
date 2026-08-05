import SwiftUI

/// Paper-white field with a thick pencil border — matches lobby player name input.
struct DoodleTextField: View {
  let placeholder: String
  @Binding var text: String
  var onSubmit: (() -> Void)?

  var body: some View {
    TextField(placeholder, text: $text)
      .themeText(.label)
      .foregroundStyle(Theme.Text.primary)
      .padding(.horizontal, Theme.Spacing.s3)
      .padding(.vertical, Theme.Spacing.s2)
      .frame(maxWidth: .infinity)
      .frame(height: Theme.Spacing.s9)
      .background(Theme.Paper.white)
      .overlay(
        RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular)
          .stroke(Theme.Stroke.default, lineWidth: Theme.Borders.thick)
      )
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
      .onSubmit { onSubmit?() }
  }
}
