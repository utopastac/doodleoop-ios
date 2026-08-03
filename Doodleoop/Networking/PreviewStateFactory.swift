import Foundation
import MultipeerConnectivity

/// Builds fake `GameState` / discovery fixtures for the view-preview menu.
/// Kept out of the production Multipeer path so `GameSession` stays focused on live play.
enum PreviewStateFactory {
  static func makePlayers(
    count: Int,
    sharedDevice: Bool,
    devicePlayerId: String,
    displayName: String,
    avatar: Drawing
  ) -> [Player] {
    let demoNames = [
      "Blake", "Casey", "Drew", "Eden", "Frankie", "Gray",
      "Harper", "Indie", "Jules", "Kip", "Logan", "Morgan",
    ]
    var players = [
      Player(id: devicePlayerId, deviceId: devicePlayerId, name: displayName, avatar: avatar),
    ]
    for i in 1..<count {
      let name = demoNames[(i - 1) % demoNames.count]
      let seatId = "sim_\(i)"
      players.append(
        Player(
          id: seatId,
          deviceId: sharedDevice ? devicePlayerId : seatId,
          name: name,
          avatar: demoDrawing(seed: i)
        )
      )
    }
    return players
  }

  static func makeLobby(players: [Player]) -> GameState {
    var lobby = GameState()
    lobby.phase = .lobby
    lobby.players = players
    lobby.hostId = players.first?.id ?? ""
    return lobby
  }

  static func makeLobby(
    playerCount: Int,
    sharedDevice: Bool,
    devicePlayerId: String,
    displayName: String,
    avatar: Drawing
  ) -> GameState {
    makeLobby(
      players: makePlayers(
        count: playerCount,
        sharedDevice: sharedDevice,
        devicePlayerId: devicePlayerId,
        displayName: displayName,
        avatar: avatar
      )
    )
  }

  static func drawingState(
    devicePlayerId: String,
    displayName: String,
    avatar: Drawing,
    now: Date = Date()
  ) -> GameState {
    let lobby = makeLobby(
      playerCount: 4,
      sharedDevice: true,
      devicePlayerId: devicePlayerId,
      displayName: displayName,
      avatar: avatar
    )
    return GameEngine.startRound(category: "Breakfast foods", in: lobby, now: now)
  }

  /// Mid-round draw turn: pads already have a guess to illustrate.
  static func drawingFromGuessState(
    devicePlayerId: String,
    displayName: String,
    avatar: Drawing,
    now: Date = Date()
  ) -> GameState {
    var next = guessingState(
      devicePlayerId: devicePlayerId,
      displayName: displayName,
      avatar: avatar,
      now: now
    )
    for player in next.players {
      next = GameEngine.submitGuess(
        playerId: player.id,
        text: demoGuess(seed: player.id.hashValue),
        in: next,
        now: now
      )
    }
    return next
  }

  static func guessingState(
    devicePlayerId: String,
    displayName: String,
    avatar: Drawing,
    now: Date = Date()
  ) -> GameState {
    var next = drawingState(
      devicePlayerId: devicePlayerId,
      displayName: displayName,
      avatar: avatar,
      now: now
    )
    for (index, player) in next.players.enumerated() {
      next = GameEngine.submitDrawing(
        playerId: player.id,
        drawing: demoDrawing(seed: index + 10),
        in: next,
        now: now
      )
    }
    return next
  }

  static func revealState(
    devicePlayerId: String,
    displayName: String,
    avatar: Drawing,
    now: Date = Date()
  ) -> GameState {
    var next = makeLobby(
      playerCount: 4,
      sharedDevice: true,
      devicePlayerId: devicePlayerId,
      displayName: displayName,
      avatar: avatar
    )
    next = GameEngine.startRound(category: "Things that float", in: next, now: now)

    // Drive a full loop: draw → guess → draw → guess.
    while next.phase == .drawing || next.phase == .guessing {
      let turn = next.turnIndex
      for (index, player) in next.players.enumerated() {
        if next.phase == .drawing {
          next = GameEngine.submitDrawing(
            playerId: player.id,
            drawing: demoDrawing(seed: turn * 10 + index + 1),
            in: next,
            now: now
          )
        } else {
          next = GameEngine.submitGuess(
            playerId: player.id,
            text: demoGuess(seed: turn * 10 + index),
            in: next,
            now: now
          )
        }
      }
    }
    return next
  }

  static func roundOverState(
    devicePlayerId: String,
    displayName: String,
    avatar: Drawing,
    now: Date = Date()
  ) -> GameState {
    var next = revealState(
      devicePlayerId: devicePlayerId,
      displayName: displayName,
      avatar: avatar,
      now: now
    )
    while next.phase == .reveal {
      next = GameEngine.advanceReveal(in: next)
    }
    return next
  }

  static func discoveredDemoPeer() -> MCPeerID {
    MCPeerID(displayName: "Peter")
  }

  /// Tiny scribble so avatar badges and reveal pads aren't empty.
  static func demoDrawing(seed: Int) -> Drawing {
    let colors = DrawingPalette.hexes
    let color = colors[abs(seed) % colors.count]
    let offset = Double(abs(seed) % 7) * 0.03
    let stroke = Stroke(
      points: [
        DrawPoint(x: 0.25 + offset, y: 0.35),
        DrawPoint(x: 0.40 + offset, y: 0.28),
        DrawPoint(x: 0.55 + offset, y: 0.40),
        DrawPoint(x: 0.48 + offset, y: 0.58),
        DrawPoint(x: 0.32 + offset, y: 0.62),
        DrawPoint(x: 0.28 + offset, y: 0.45),
      ],
      lineWidth: DrawingTool.pen.defaultWidth,
      tool: .pen,
      colorHex: color
    )
    let accent = Stroke(
      points: [
        DrawPoint(x: 0.58 + offset, y: 0.30),
        DrawPoint(x: 0.72 + offset, y: 0.45),
        DrawPoint(x: 0.65 + offset, y: 0.68),
      ],
      lineWidth: DrawingTool.pencil.defaultWidth,
      tool: .pencil,
      colorHex: DrawingPalette.hexes[(abs(seed) + 3) % colors.count]
    )
    return Drawing(strokes: [stroke, accent])
  }

  private static func demoGuess(seed: Int) -> String {
    let guesses = [
      "a rubber duck",
      "pancakes",
      "a submarine",
      "toast with jam",
      "a hot air balloon",
      "cereal bowl",
    ]
    return guesses[abs(seed) % guesses.count]
  }
}
