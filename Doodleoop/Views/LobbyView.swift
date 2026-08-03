import SwiftUI

struct LobbyView: View {
  @EnvironmentObject private var session: GameSession
  @State private var extraName = ""

  var body: some View {
    let state = session.state ?? GameState()

    NavigationStack {
      VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
        Text(session.isHost ? "Your lobby" : "Lobby")
          .themeText(.heading)
          .foregroundStyle(Theme.Text.primary)
          .padding(.trailing, Theme.Sizing.leaveButtonReserve)

        Text("\(state.players.count) players · pass drawings to the left")
          .themeText(.labelSmall)
          .foregroundStyle(Theme.Text.secondary)

        Text("Draw \(state.drawTimeLimitSeconds)s · Guess \(state.guessTimeLimitSeconds)s")
          .themeText(.label)
          .foregroundStyle(Theme.Text.tertiary)

        NavigationLink {
          GameSettingsView()
        } label: {
          Label("Game settings", systemImage: "timer")
            .themeText(.bodyStrong)
            .foregroundStyle(Theme.Interactive.link)
        }

        List {
          ForEach(state.players) { player in
            HStack(spacing: Theme.Spacing.s3) {
              AvatarBadge(drawing: player.avatar, size: Theme.Sizing.avatarMd)
              Text(player.name)
                .themeText(.bodyStrong)
                .foregroundStyle(Theme.Text.primary)
              Spacer()
              if player.id == state.hostId {
                Text("Host")
                  .themeText(.caption)
                  .foregroundStyle(Theme.Accent.default)
              }
              if player.deviceId == session.localDeviceId && player.id != session.devicePlayerId {
                Button("Remove") {
                  session.removeLocalSeat(player.id)
                }
                .themeText(.caption)
                .foregroundStyle(Theme.Interactive.link)
              }
            }
            .listRowBackground(Theme.Background.primary)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)

        if session.role == .joiner, session.state == nil || session.state?.players.isEmpty == true {
          ProgressView("Looking for games…")
            .tint(Theme.Accent.default)
        }

        if session.role == .joiner && !session.discoveredPeers.isEmpty {
          Text("Nearby games")
            .themeText(.bodyStrong)
            .foregroundStyle(Theme.Text.primary)
          ForEach(session.discoveredPeers, id: \.displayName) { peer in
            Button(peer.displayName) {
              session.join(peer)
            }
            .doodleButton(.secondary)
          }
        }

        HStack {
          TextField("Add seat on this phone", text: $extraName)
            .themeText(.label)
            .textFieldStyle(.roundedBorder)
          Button("Add") {
            session.addLocalSeat(name: extraName)
            extraName = ""
          }
          .themeText(.button)
          .foregroundStyle(Theme.Accent.default)
          .disabled(state.phase != .lobby)
        }

        if session.isHost {
          TextField("Category for this round", text: $session.draftCategory)
            .themeText(.label)
            .textFieldStyle(.roundedBorder)

          Button(DoodleLabel.bracketed("Start round")) {
            session.startRound()
          }
          .doodleButton(.primary)
          .disabled(state.players.count < 2 || session.draftCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .padding(.horizontal, Theme.Layout.pageMargin)
      .padding(.top, Theme.Spacing.s3)
      .paperBackground()
      .pageMargins()
    }
  }
}
