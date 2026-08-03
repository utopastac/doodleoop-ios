import SwiftUI

struct RevealView: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    let state = session.state
    let pad = state.flatMap { $0.pads.indices.contains($0.revealPadIndex) ? $0.pads[$0.revealPadIndex] : nil }
    let starter = pad.flatMap { state?.player(id: $0.id) }

    VStack(spacing: Theme.Spacing.s4) {
      Text("Reveal")
        .themeText(.heading)
        .foregroundStyle(Theme.Text.primary)
      if let starter {
        Text("Started by \(starter.name)")
          .themeText(.label)
          .foregroundStyle(Theme.Text.secondary)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
          if let pad {
            ForEach(Array(pad.steps.enumerated()), id: \.offset) { _, step in
              switch step {
              case .prompt(let text):
                labeled("Category", text)
              case .drawing(let playerId, let drawing):
                VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
                  Text(state?.player(id: playerId)?.name ?? "Player")
                    .themeText(.bodyStrong)
                    .foregroundStyle(Theme.Text.primary)
                  ReadOnlyDrawingView(drawing: drawing)
                    .frame(height: 220)
                }
              case .guess(let playerId, let text):
                labeled(state?.player(id: playerId)?.name ?? "Player", text)
              }
            }
          }
        }
        .pageHorizontalPadding()
      }

      if session.isHost {
        Button(DoodleLabel.bracketed(state.map { $0.revealPadIndex + 1 >= $0.pads.count } == true ? "Finish" : "Next pad")) {
          session.advanceReveal()
        }
        .doodleButton(.primary)
        .pageHorizontalPadding()
        .padding(.bottom, Theme.Spacing.s3)
      } else {
        Text("Host is revealing…")
          .themeText(.label)
          .foregroundStyle(Theme.Text.secondary)
          .padding(.bottom, Theme.Spacing.s3)
      }
    }
    .padding(.top, Theme.Spacing.s5)
    .paperBackground(.plain)
    .pageMargins()
  }

  private func labeled(_ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
      Text(title)
        .themeText(.caption)
        .foregroundStyle(Theme.Accent.default)
      Text(body)
        .themeText(.subheading)
        .foregroundStyle(Theme.Text.primary)
    }
  }
}

struct RoundOverView: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    VStack(spacing: Theme.Spacing.s6) {
      Spacer()
      Text("Loop complete")
        .themeText(.heading)
        .foregroundStyle(Theme.Text.primary)
      Text("Ready for another category?")
        .themeText(.label)
        .foregroundStyle(Theme.Text.secondary)
      if session.isHost {
        Button(DoodleLabel.bracketed("Back to lobby")) {
          session.returnToLobby()
        }
        .doodleButton(.primary)
        .pageHorizontalPadding()
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperBackground(.plain)
    .pageMargins()
  }
}

struct HandoffOverlay: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    if let handoff = session.handoff,
       let player = session.state?.player(id: handoff.playerId) {
      ZStack {
        Theme.Ink.deep.opacity(0.94).ignoresSafeArea()
        VStack(spacing: Theme.Spacing.s5) {
          Text(handoff.title)
            .themeText(.heading)
            .foregroundStyle(Theme.Background.primary)
          Text(handoff.message)
            .themeText(.label)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.Background.primary.opacity(0.85))
            .padding(.horizontal, Theme.Spacing.s7)
          AvatarBadge(drawing: player.avatar, size: 120)
          Text(player.name)
            .themeText(.display)
            .foregroundStyle(Theme.Accent.muted)
          Button(DoodleLabel.bracketed("I'm \(player.name)")) {
            session.confirmHandoff()
          }
          .doodleButton(.primary)
          .pageHorizontalPadding()
        }
      }
    }
  }
}
