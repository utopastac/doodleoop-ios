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
  var avatar: Drawing

  init(id: String, deviceId: String, name: String, avatar: Drawing = .empty) {
    self.id = id
    self.deviceId = deviceId
    self.name = name
    self.avatar = avatar
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    deviceId = try container.decode(String.self, forKey: .deviceId)
    name = try container.decode(String.self, forKey: .name)
    avatar = try container.decodeIfPresent(Drawing.self, forKey: .avatar) ?? .empty
  }
}

struct DrawPoint: Codable, Equatable {
  var x: Double
  var y: Double
  /// Per-point brush width (pen speed dynamics). Nil → use the stroke’s `lineWidth`.
  var lineWidth: Double?

  init(x: Double, y: Double, lineWidth: Double? = nil) {
    self.x = x
    self.y = y
    self.lineWidth = lineWidth
  }
}

enum DrawingTool: String, Codable, CaseIterable, Equatable {
  case pencil
  case pen
  case highlighter

  var displayName: String {
    switch self {
    case .pencil: return "Pencil"
    case .pen: return "Pen"
    case .highlighter: return "Highlighter"
    }
  }

  var systemImage: String {
    switch self {
    case .pencil: return "pencil"
    case .pen: return "pencil.tip"
    case .highlighter: return "highlighter"
    }
  }

  /// Soft graphite vs solid ink vs translucent marker wash.
  var opacity: Double {
    switch self {
    case .pencil: return 0.72
    case .pen: return 1.0
    case .highlighter: return 0.38
    }
  }

  var defaultWidth: Double {
    switch self {
    case .pencil: return 3
    case .pen: return 4
    case .highlighter: return 18
    }
  }

  var availableWidths: [Double] {
    switch self {
    case .pencil: return [1.5, 3, 6]
    case .pen: return [2, 4, 8]
    case .highlighter: return [12, 18, 28]
    }
  }

  /// Highlighter uses a flatter tip; pencil/pen are round.
  var usesFlatTip: Bool { self == .highlighter }
}

/// Simple 10-swatch ink set for doodling.
enum DrawingPalette {
  static let hexes: [String] = [
    "#1F2329", // ink
    "#6B7280", // slate
    "#E85A54", // coral
    "#F08A3A", // orange
    "#E6AD2E", // mustard
    "#3D9A4A", // green
    "#1F8C85", // teal
    "#3B6FD9", // blue
    "#7B5CDB", // purple
    "#E05A9A", // pink
  ]

  static let defaultHex = hexes[0]
}

struct Stroke: Codable, Equatable, Identifiable {
  var id: UUID
  var points: [DrawPoint]
  var lineWidth: Double
  var tool: DrawingTool
  /// Hex color like `#1F2329` (no alpha — tool opacity applies at render).
  var colorHex: String

  init(
    id: UUID = UUID(),
    points: [DrawPoint] = [],
    lineWidth: Double = DrawingTool.pen.defaultWidth,
    tool: DrawingTool = .pen,
    colorHex: String = DrawingPalette.defaultHex
  ) {
    self.id = id
    self.points = points
    self.lineWidth = lineWidth
    self.tool = tool
    self.colorHex = colorHex
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    points = try container.decode([DrawPoint].self, forKey: .points)
    lineWidth = try container.decodeIfPresent(Double.self, forKey: .lineWidth) ?? DrawingTool.pen.defaultWidth
    tool = try container.decodeIfPresent(DrawingTool.self, forKey: .tool) ?? .pen
    colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? DrawingPalette.defaultHex
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

enum GameTimerDefaults {
  static let drawSeconds = 60
  static let guessSeconds = 30
  static let minSeconds = 5
  static let maxSeconds = 300
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
  /// Seconds allowed for each drawing turn.
  var drawTimeLimitSeconds: Int = GameTimerDefaults.drawSeconds
  /// Seconds allowed for each guessing turn.
  var guessTimeLimitSeconds: Int = GameTimerDefaults.guessSeconds
  /// Host-authored deadline for the current drawing/guessing turn.
  var phaseEndsAt: Date?

  init(
    phase: GamePhase = .lobby,
    players: [Player] = [],
    hostId: String = "",
    category: String = "",
    pads: [SketchPad] = [],
    turnIndex: Int = 0,
    submittedPlayerIds: Set<String> = [],
    revealPadIndex: Int = 0,
    drawTimeLimitSeconds: Int = GameTimerDefaults.drawSeconds,
    guessTimeLimitSeconds: Int = GameTimerDefaults.guessSeconds,
    phaseEndsAt: Date? = nil
  ) {
    self.phase = phase
    self.players = players
    self.hostId = hostId
    self.category = category
    self.pads = pads
    self.turnIndex = turnIndex
    self.submittedPlayerIds = submittedPlayerIds
    self.revealPadIndex = revealPadIndex
    self.drawTimeLimitSeconds = drawTimeLimitSeconds
    self.guessTimeLimitSeconds = guessTimeLimitSeconds
    self.phaseEndsAt = phaseEndsAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    phase = try container.decode(GamePhase.self, forKey: .phase)
    players = try container.decode([Player].self, forKey: .players)
    hostId = try container.decode(String.self, forKey: .hostId)
    category = try container.decode(String.self, forKey: .category)
    pads = try container.decode([SketchPad].self, forKey: .pads)
    turnIndex = try container.decode(Int.self, forKey: .turnIndex)
    submittedPlayerIds = try container.decode(Set<String>.self, forKey: .submittedPlayerIds)
    revealPadIndex = try container.decode(Int.self, forKey: .revealPadIndex)
    drawTimeLimitSeconds = try container.decodeIfPresent(Int.self, forKey: .drawTimeLimitSeconds)
      ?? GameTimerDefaults.drawSeconds
    guessTimeLimitSeconds = try container.decodeIfPresent(Int.self, forKey: .guessTimeLimitSeconds)
      ?? GameTimerDefaults.guessSeconds
    phaseEndsAt = try container.decodeIfPresent(Date.self, forKey: .phaseEndsAt)
  }

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

  var currentTurnTimeLimitSeconds: Int {
    isDrawTurn ? drawTimeLimitSeconds : guessTimeLimitSeconds
  }
}
