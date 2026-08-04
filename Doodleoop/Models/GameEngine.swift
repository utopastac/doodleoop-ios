import Foundation

enum GameEngine {
  static func addPlayer(
    id: String,
    name: String,
    deviceId: String,
    avatar: Drawing = .empty,
    to state: GameState
  ) -> GameState {
    var next = state
    guard next.phase == .lobby else { return state }
    guard !next.players.contains(where: { $0.id == id }) else { return state }
    next.players.append(Player(id: id, deviceId: deviceId, name: name, avatar: avatar))
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

  static func updateAvatar(playerId: String, avatar: Drawing, in state: GameState) -> GameState {
    var next = state
    guard let index = next.playerIndex(playerId) else { return state }
    next.players[index].avatar = avatar
    return next
  }

  /// Host-only lobby settings for turn timers and round length.
  static func updateSettings(
    drawTimeLimitSeconds: Int,
    guessTimeLimitSeconds: Int,
    maxRounds: Int? = nil,
    in state: GameState
  ) -> GameState {
    var next = state
    guard next.phase == .lobby || next.phase == .roundOver else { return state }
    next.drawTimeLimitSeconds = clampTimeLimit(drawTimeLimitSeconds)
    next.guessTimeLimitSeconds = clampTimeLimit(guessTimeLimitSeconds)
    if let maxRounds {
      next.maxRounds = clampMaxRounds(maxRounds)
    }
    return next
  }

  /// Starts a round: every seat draws the shared category first.
  static func startRound(category: String, in state: GameState, now: Date = Date()) -> GameState {
    var next = state
    let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
    guard next.phase == .lobby || next.phase == .roundOver else { return state }
    guard next.players.count >= 2, !trimmed.isEmpty else { return state }

    next.category = trimmed
    next.turnIndex = 0
    next.submittedPlayerIds = []
    next.revealPadIndex = 0
    next.revealStepIndex = 0
    next.pads = next.players.map { player in
      SketchPad(id: player.id, steps: [.prompt(trimmed)])
    }
    next.phase = .drawing
    next.phaseEndsAt = now.addingTimeInterval(TimeInterval(next.drawTimeLimitSeconds))
    return next
  }

  static func submitDrawing(
    playerId: String,
    drawing: Drawing,
    in state: GameState,
    now: Date = Date()
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
    return advanceIfReady(next, now: now)
  }

  static func submitGuess(
    playerId: String,
    text: String,
    in state: GameState,
    now: Date = Date()
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
    return advanceIfReady(next, now: now)
  }

  /// When the turn timer expires, fill missing submissions and advance.
  static func expireTurn(in state: GameState, now: Date = Date()) -> GameState {
    var next = state
    guard next.phase == .drawing || next.phase == .guessing else { return state }
    guard let ends = next.phaseEndsAt, now >= ends else { return state }

    for player in next.players where !next.submittedPlayerIds.contains(player.id) {
      guard var pad = next.pad(inFrontOf: player.id),
            let padIndex = next.pads.firstIndex(where: { $0.id == pad.id }) else { continue }
      if next.phase == .drawing {
        pad.steps.append(.drawing(playerId: player.id, drawing: .empty))
      } else {
        pad.steps.append(.guess(playerId: player.id, text: "…"))
      }
      next.pads[padIndex] = pad
      next.submittedPlayerIds.insert(player.id)
    }

    return advanceIfReady(next, now: now)
  }

  /// Reveals the next contribution on the current pad, then moves to the next pad,
  /// then ends the round. Synced to every device via `syncState`.
  static func advanceReveal(in state: GameState) -> GameState {
    var next = state
    guard next.phase == .reveal else { return state }
    let contributions = next.currentRevealContributions
    if next.revealStepIndex < contributions.count {
      next.revealStepIndex += 1
    } else if next.revealPadIndex + 1 < next.pads.count {
      next.revealPadIndex += 1
      next.revealStepIndex = min(1, next.currentRevealContributions.count)
    } else {
      next.phase = .roundOver
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
    next.revealStepIndex = 0
    next.phaseEndsAt = nil
    return next
  }

  private static func advanceIfReady(_ state: GameState, now: Date) -> GameState {
    var next = state
    guard next.allSubmitted else { return next }

    next.submittedPlayerIds = []
    next.turnIndex += 1

    if next.isRoundComplete {
      next.phase = .reveal
      next.revealPadIndex = 0
      // Start with the first drawing already visible on pad 0.
      next.revealStepIndex = min(1, next.currentRevealContributions.count)
      next.phaseEndsAt = nil
      return next
    }

    next.phase = next.isDrawTurn ? .drawing : .guessing
    next.phaseEndsAt = now.addingTimeInterval(TimeInterval(next.currentTurnTimeLimitSeconds))
    return next
  }

  private static func clampTimeLimit(_ seconds: Int) -> Int {
    min(max(seconds, GameTimerDefaults.minSeconds), GameTimerDefaults.maxSeconds)
  }

  private static func clampMaxRounds(_ rounds: Int) -> Int {
    min(max(rounds, GameRoundDefaults.minRounds), GameRoundDefaults.absoluteMaxRounds)
  }
}
