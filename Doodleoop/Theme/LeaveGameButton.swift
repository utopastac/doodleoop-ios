import SwiftUI

/// Ink square close control — confirms, then calls `GameSession.leaveGame()`.
struct LeaveGameButton: View {
  @EnvironmentObject private var session: GameSession
  @State private var showConfirm = false

  var body: some View {
    Button {
      showConfirm = true
    } label: {
      PhosphorIcon.x.image
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
        .frame(width: Theme.Sizing.iconMd, height: Theme.Sizing.iconMd)
        .foregroundStyle(Theme.Paper.tan)
        .frame(width: Theme.Sizing.inputHeight, height: Theme.Sizing.inputHeight)
        .background(Theme.Ink.deep)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Leave game")
    .confirmationDialog(
      session.isHost ? "End this game?" : "Leave this game?",
      isPresented: $showConfirm,
      titleVisibility: .visible
    ) {
      Button(session.isHost ? "End game" : "Leave game", role: .destructive) {
        session.leaveGame()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        session.isHost
          ? "This disconnects everyone and ends the session."
          : "You'll disconnect. Other players can keep going."
      )
    }
  }
}

/// Pins a leave control to the top-trailing corner of in-game screens.
struct LeaveGameChrome: ViewModifier {
  func body(content: Content) -> some View {
    content.overlay(alignment: .topTrailing) {
      LeaveGameButton()
        .padding(.top, Theme.Spacing.s3)
        .padding(.trailing, Theme.Layout.pageMargin)
    }
  }
}

extension View {
  /// Always-on leave control for lobby / round / reveal screens.
  func leaveGameChrome() -> some View {
    modifier(LeaveGameChrome())
  }
}
