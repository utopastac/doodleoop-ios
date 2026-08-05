import SwiftUI

/// Ink square leave control — confirms, then calls `GameSession.leaveGame()`.
struct LeaveGameButton: View {
  @Environment(GameSession.self) private var session
  @State private var showConfirm = false

  /// Figma primary icon button — 40×40 with 20pt glyph.
  var size: CGFloat = Theme.Spacing.s8

  var body: some View {
    DoodleIconButton(
      phosphor: .signOut,
      variant: .ink,
      size: size,
      accessibilityLabel: "Leave game"
    ) {
      showConfirm = true
    }
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

/// Pins a leave control to the top-trailing corner of in-game screens
/// (drawing / guessing). Lobby, reveal and round-over own an inline leave band.
struct LeaveGameChrome: ViewModifier {
  var isEnabled: Bool = true

  func body(content: Content) -> some View {
    content.overlay(alignment: .topTrailing) {
      if isEnabled {
        LeaveGameButton()
          .padding(.top, Theme.Spacing.s3)
          .padding(.trailing, Theme.Layout.pageMargin)
      }
    }
  }
}

extension View {
  /// Overlay leave control for drawing / guessing.
  func leaveGameChrome(isEnabled: Bool = true) -> some View {
    modifier(LeaveGameChrome(isEnabled: isEnabled))
  }
}
