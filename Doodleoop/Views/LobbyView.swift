import SwiftUI

struct LobbyView: View {
  @EnvironmentObject private var session: GameSession
  @State private var extraName = ""

  var body: some View {
    let state = session.state ?? GameState()

    NavigationStack {
      VStack(alignment: .leading, spacing: 20) {
        Text(session.isHost ? "Your lobby" : "Lobby")
          .font(.largeTitle.weight(.black))

        Text("\(state.players.count) players · pass drawings to the left")
          .foregroundStyle(.secondary)

        List {
          ForEach(state.players) { player in
            HStack {
              Text(player.name)
                .font(.headline)
              Spacer()
              if player.id == state.hostId {
                Text("Host")
                  .font(.caption.weight(.bold))
                  .foregroundStyle(Theme.coral)
              }
              if player.deviceId == session.localDeviceId && player.id != session.devicePlayerId {
                Button("Remove") {
                  session.removeLocalSeat(player.id)
                }
                .font(.caption)
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
            .font(.headline)
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
