import SwiftUI

struct LobbyView: View {
  @EnvironmentObject private var session: GameSession
  @State private var extraName = ""

  var body: some View {
    let state = session.state ?? GameState()

    NavigationStack {
      VStack(alignment: .leading, spacing: 20) {
        Text(session.isHost ? "Your lobby" : "Lobby")
          .font(Theme.Fonts.largeTitle)

        Text("\(state.players.count) players · pass drawings to the left")
          .foregroundStyle(.secondary)

        Text("Draw \(state.drawTimeLimitSeconds)s · Guess \(state.guessTimeLimitSeconds)s")
          .font(Theme.Fonts.subheadline)
          .foregroundStyle(Theme.ink.opacity(0.65))

        NavigationLink {
          GameSettingsView()
        } label: {
          Label("Game settings", systemImage: "timer")
            .font(Theme.Fonts.headline)
            .foregroundStyle(Theme.teal)
        }

        List {
          ForEach(state.players) { player in
            HStack(spacing: 12) {
              AvatarBadge(drawing: player.avatar, size: 40)
              Text(player.name)
                .font(Theme.Fonts.headline)
              Spacer()
              if player.id == state.hostId {
                Text("Host")
                  .font(Theme.Fonts.caption)
                  .foregroundStyle(Theme.coral)
              }
              if player.deviceId == session.localDeviceId && player.id != session.devicePlayerId {
                Button("Remove") {
                  session.removeLocalSeat(player.id)
                }
                .font(Theme.Fonts.caption)
              }
            }
          }
        }
        .listStyle(.plain)

        if session.role == .joiner, session.state == nil || session.state?.players.isEmpty == true {
          ProgressView("Looking for games…")
        }

        if session.role == .joiner && !session.discoveredPeers.isEmpty {
          Text("Nearby games")
            .font(Theme.Fonts.headline)
          ForEach(session.discoveredPeers, id: \.displayName) { peer in
            Button(peer.displayName) {
              session.join(peer)
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.teal))
          }
        }

        HStack {
          TextField("Add seat on this phone", text: $extraName)
            .textFieldStyle(.roundedBorder)
          Button("Add") {
            session.addLocalSeat(name: extraName)
            extraName = ""
          }
          .disabled(state.phase != .lobby)
        }

        if session.isHost {
          TextField("Category for this round", text: $session.draftCategory)
            .textFieldStyle(.roundedBorder)

          Button("Start round") {
            session.startRound()
          }
          .buttonStyle(PrimaryButtonStyle(color: Theme.coral))
          .disabled(state.players.count < 2 || session.draftCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        Button("Leave", role: .destructive) {
          session.leaveGame()
        }
      }
      .padding(20)
      .background(Theme.paper.ignoresSafeArea())
    }
  }
}
