import Foundation

/// Wire protocol between host and joiners.
enum NetworkMessage: Codable, Equatable {
  case syncState(GameState)
  case hello(playerId: String, name: String, avatar: Drawing)
  case setName(playerId: String, name: String)
  case setAvatar(playerId: String, avatar: Drawing)
  case addPlayer(playerId: String, name: String)
  case removePlayer(playerId: String)
  case startRound(category: String)
  case submitDrawing(playerId: String, drawing: Drawing)
  case submitGuess(playerId: String, text: String)
  case advanceReveal
  case returnToLobby
  case leave
}
