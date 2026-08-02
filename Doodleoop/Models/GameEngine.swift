import Foundation

enum GameEngine {
  static func addPlayer(
    id: String,
    name: String,
    deviceId: String,
    to state: GameState
  ) -> GameState {
    var next = state
    guard next.phase == .lobby else { return state }
    guard !next.players.contains(where: { $0.id == id }) else { return state }
    next.players.append(Player(id: id, deviceId: deviceId, name: name))
    if next.hostId.isEmpty {
      next.hostId = id
    }
    return next
  }

  static func removePlayer(id: String, from state: GameState) -> GameState {
    var next = state
    guard next.phase == .lobby else { return state }
    next.players.removeAll { $0.id == id }
    if next.hostId == id {
      next.hostId = next.players.first?.id ?? ""
    }
    return next
  }

  static func removePlayers(deviceId: String, from state: GameState) -> GameState {
    var next = state
    let ids = next.players.filter { $0.deviceId == deviceId }.map(\.id)
    for id in ids {
      next = removePlayer(id: id, from: next)
    }
    return next
  }

  static func updateName(playerId: String, name: String, in state: GameState) -> GameState {
    var next = state
    guard let index = next.playerIndex(playerId) else { return state }
    next.players[index].name = name
    return next
  }

  /// Starts a round: every seat draws the shared category first.
  static func startRound(category: String, in state: GameState) -> GameState {
    var next = state
    let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
    guard next.phase == .lobby || next.phase == .roundOver else { return state }
    guard next.players.count >= 2, !trimmed.isEmpty else { return state }

    next.category = trimmed
    next.turnIndex = 0
    next.submittedPlayerIds = []
    next.revealPadIndex = 0
    next.pads = next.players.map { player in
      SketchPad(id: player.id, steps: [.prompt(trimmed)])
    }
    next.phase = .drawing
    return next
  }

  static func submitDrawing(
    playerId: String,
    drawing: Drawing,
    in state: GameState
  ) -> GameState {
    var next = state
    guard next.phase == .drawing, next.isDrawTurn else { return state }
    guard next.players.contains(where: { $0.id == playerId }) else { return state }
    guard !next.submittedPlayerIds.contains(playerId) else { return state }
    guard !drawing.isEmpty else { return state }
    guard var pad = next.pad(inFrontOf: playerId),
          let padIndex = next.pads.firstIndex(where: { $0.id == pad.id }) else { return state }

    pad.steps.append(.drawing(playerId: playerId, drawing: drawing))
    next.pads[padIndex] = pad
    next.submittedPlayerIds.insert(playerId)
    return advanceIfReady(next)
  }

  static func submitGuess(
    playerId: String,
    text: String,
    in state: GameState
  ) -> GameState {
    var next = state
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard next.phase == .guessing, !next.isDrawTurn else { return state }
    guard next.players.contains(where: { $0.id == playerId }) else { return state }
    guard !next.submittedPlayerIds.contains(playerId) else { return state }
    guard !trimmed.isEmpty else { return state }
    guard var pad = next.pad(inFrontOf: playerId),
          let padIndex = next.pads.firstIndex(where: { $0.id == pad.id }) else { return state }

    pad.steps.append(.guess(playerId: playerId, text: trimmed))
    next.pads[padIndex] = pad
    next.submittedPlayerIds.insert(playerId)
    return advanceIfReady(next)
  }

  static func advanceReveal(in state: GameState) -> GameState {
    var next = state
    guard next.phase == .reveal else { return state }
    if next.revealPadIndex + 1 >= next.pads.count {
      next.phase = .roundOver
    } else {
      next.revealPadIndex += 1
    }
    return next
  }

  static func returnToLobby(in state: GameState) -> GameState {
    var next = state
    next.phase = .lobby
    next.category = ""
    next.pads = []
    next.turnIndex = 0
    next.submittedPlayerIds = []
    next.revealPadIndex = 0
    return next
  }

  private static func advanceIfReady(_ state: GameState) -> GameState {
    var next = state
    guard next.allSubmitted else { return next }

    next.submittedPlayerIds = []
    next.turnIndex += 1

    if next.isRoundComplete {
      next.phase = .reveal
      next.revealPadIndex = 0
      return next
    }

    next.phase = next.isDrawTurn ? .drawing : .guessing
    return next
  }
}
