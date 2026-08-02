import Foundation

enum GamePhase: String, Codable, Equatable {
  case lobby
  case drawing
  case guessing
  case reveal
  case roundOver
}

struct Player: Identifiable, Codable, Equatable {
  let id: String
  var deviceId: String
  var name: String
}

struct DrawPoint: Codable, Equatable {
  var x: Double
  var y: Double
}

struct Stroke: Codable, Equatable, Identifiable {
  var id: UUID
  var points: [DrawPoint]
  var lineWidth: Double

  init(id: UUID = UUID(), points: [DrawPoint] = [], lineWidth: Double = 4) {
    self.id = id
    self.points = points
    self.lineWidth = lineWidth
  }
}

struct Drawing: Codable, Equatable {
  var strokes: [Stroke]

  static let empty = Drawing(strokes: [])

  var isEmpty: Bool { strokes.allSatisfy(\.points.isEmpty) || strokes.isEmpty }
}

enum ChainStep: Codable, Equatable, Identifiable {
  case prompt(String)
  case drawing(playerId: String, drawing: Drawing)
  case guess(playerId: String, text: String)

  var id: String {
    switch self {
    case .prompt(let text):
      return "prompt:\(text)"
    case .drawing(let playerId, _):
      return "drawing:\(playerId)"
    case .guess(let playerId, let text):
      return "guess:\(playerId):\(text)"
    }
  }
}

/// One pad that travels left around the circle.
struct SketchPad: Identifiable, Codable, Equatable {
  /// Seat that started this pad (first drawer).
  let id: String
  var steps: [ChainStep]
}

struct GameState: Codable, Equatable {
  var phase: GamePhase = .lobby
  var players: [Player] = []
  var hostId: String = ""
  var category: String = ""
  /// Pads indexed by starting player id.
  var pads: [SketchPad] = []
  /// How many simultaneous turns have completed (0..<playerCount).
  var turnIndex: Int = 0
  /// playerId → submitted for current turn
  var submittedPlayerIds: Set<String> = []
  /// Which pad is currently being shown in reveal (by starter id).
  var revealPadIndex: Int = 0

  func player(id: String) -> Player? {
    players.first { $0.id == id }
  }

  func playerIndex(_ id: String) -> Int? {
    players.firstIndex { $0.id == id }
  }

  /// Pad currently sitting in front of `playerId` for this turn.
  func pad(inFrontOf playerId: String) -> SketchPad? {
    guard let holderIndex = playerIndex(playerId), !pads.isEmpty else { return nil }
    let startIndex = (holderIndex - turnIndex + players.count) % players.count
    return pads.first { $0.id == players[startIndex].id }
  }

  var isDrawTurn: Bool { turnIndex % 2 == 0 }

  var allSubmitted: Bool {
    !players.isEmpty && submittedPlayerIds.count >= players.count
  }

  var isRoundComplete: Bool {
    !players.isEmpty && turnIndex >= players.count
  }
}
