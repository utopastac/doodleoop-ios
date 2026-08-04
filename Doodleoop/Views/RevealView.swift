import SwiftUI

struct RevealView: View {
  @EnvironmentObject private var session: GameSession

  var body: some View {
    let state = session.state
    let pad = state.flatMap { $0.pads.indices.contains($0.revealPadIndex) ? $0.pads[$0.revealPadIndex] : nil }
    let starter = pad.flatMap { state?.player(id: $0.id) }
    let visible = state?.visibleRevealContributions ?? []
    let finished = state?.isRevealFinished == true

    VStack(spacing: Theme.Spacing.s4) {
      Text("Reveal")
        .themeText(.heading)
        .foregroundStyle(Theme.Text.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, Theme.Sizing.leaveButtonReserve)
        .pageHorizontalPadding()

      if let starter {
        Text("\(starter.name)'s pad")
          .themeText(.label)
          .foregroundStyle(Theme.Text.secondary)
          .pageHorizontalPadding()
      }

      if let category = state?.category, !category.isEmpty {
        labeled("Category", category)
          .pageHorizontalPadding()
      }

      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, step in
              stepView(step, state: state)
                .id(index)
            }
          }
          .pageHorizontalPadding()
          .padding(.bottom, Theme.Spacing.s4)
        }
        .onChange(of: visible.count) { _, count in
          guard count > 0 else { return }
          withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(count - 1, anchor: .bottom)
          }
        }
        .onChange(of: state?.revealPadIndex) { _, _ in
          guard !visible.isEmpty else { return }
          withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(0, anchor: .top)
          }
        }
      }

      Button(DoodleLabel.bracketed(finished ? "Finish" : "Next")) {
        session.advanceReveal()
      }
      .doodleButton(.primary)
      .pageHorizontalPadding()
      .padding(.bottom, Theme.Spacing.s3)
    }
    .padding(.top, Theme.Spacing.s5)
    .paperBackground()
    .pageMargins()
  }

  @ViewBuilder
  private func stepView(_ step: ChainStep, state: GameState?) -> some View {
    switch step {
    case .prompt(let text):
      labeled("Category", text)
    case .drawing(let playerId, let drawing):
      VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
        Text(state?.player(id: playerId)?.name ?? "Player")
          .themeText(.bodyStrong)
          .foregroundStyle(Theme.Text.primary)
        ReadOnlyDrawingView(drawing: drawing)
          .aspectRatio(1, contentMode: .fit)
      }
    case .guess(let playerId, let text):
      labeled(state?.player(id: playerId)?.name ?? "Player", text)
    }
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
      Text("Every drawing book was saved to History on this phone.")
        .themeText(.label)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.Text.secondary)
        .pageHorizontalPadding()
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
    .paperBackground()
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
