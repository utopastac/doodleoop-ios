import SwiftUI

/// 40pt band with an optional title and trailing leave control — lobby, reveal, round-over.
struct LeaveToolbarBand: View {
  var title: String?

  var body: some View {
    HStack(spacing: 0) {
      if let title {
        Text(title)
          .themeText(.body)
          .foregroundStyle(Theme.Text.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityAddTraits(.isHeader)
      } else {
        Spacer(minLength: 0)
      }

      LeaveGameButton()
    }
    .frame(height: Theme.Spacing.s8)
    .pageHorizontalPadding()
  }
}
