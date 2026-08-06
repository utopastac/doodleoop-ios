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
  case eraser

  var displayName: String {
    switch self {
    case .pencil: return "Pencil"
    case .pen: return "Pen"
    case .highlighter: return "Highlighter"
    case .eraser: return "Eraser"
    }
  }

  /// Soft graphite vs solid ink vs translucent marker wash.
  var opacity: Double {
    switch self {
    case .pencil: return 0.72
    case .pen: return 1.0
    case .highlighter: return 0.38
    case .eraser: return 1.0
    }
  }

  var defaultWidth: Double {
    switch self {
    case .pencil: return 8
    case .pen: return 10
    case .highlighter: return 24
    case .eraser: return 24
    }
  }

  /// Four nib sizes — matches the drawing-page brush-size row.
  var availableWidths: [Double] {
    switch self {
    case .pencil: return [3, 8, 16, 28]
    case .pen: return [4, 10, 18, 32]
    case .highlighter: return [14, 24, 40, 56]
    case .eraser: return [12, 24, 40, 64]
    }
  }

  /// Highlighter uses a flatter tip; pencil/pen/eraser are round.
  var usesFlatTip: Bool { self == .highlighter }

  var isEraser: Bool { self == .eraser }
}

/// Drawing-page swatches (Figma Drawing → swatches).
enum DrawingPalette {
  static let hexes: [String] = [
    "#FFFFFF", // white
    "#000000", // black
    "#6176FF", // blue
    "#56CD38", // green
    "#EC6363", // red
    "#EEDB4D", // yellow
    "#EF68C8", // pink
    "#EE9048", // orange
  ]

  /// Default to black — white is available but a poor first stroke.
  static let defaultHex = hexes[1]
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

enum GameRoundDefaults {
  static let maxRounds = 8
  static let minRounds = 2
  static let absoluteMaxRounds = 16
}

struct GameState: Codable, Equatable {
  var phase: GamePhase = .lobby
  var players: [Player] = []
  var hostId: String = ""
  /// Stable id for this lobby/game — used to find the room after host migration.
  var roomId: String = ""
  /// Device currently running the network host / game engine.
  var networkHostDeviceId: String = ""
  /// Bumps on each host migration so stale hosts lose authority.
  var stateEpoch: Int = 0
  var category: String = ""
  /// Pads indexed by starting player id.
  var pads: [SketchPad] = []
  /// How many simultaneous turns have completed (0..<effectiveTurnCount).
  var turnIndex: Int = 0
  /// playerId → submitted for current turn
  var submittedPlayerIds: Set<String> = []
  /// Which pad is currently being shown in reveal (by starter id).
  var revealPadIndex: Int = 0
  /// How many contribution steps (drawings/guesses) are visible on the current pad.
  /// Category/prompt is shown as context; contributions append one at a time.
  var revealStepIndex: Int = 0
  /// Seconds allowed for each drawing turn.
  var drawTimeLimitSeconds: Int = GameTimerDefaults.drawSeconds
  /// Seconds allowed for each guessing turn.
  var guessTimeLimitSeconds: Int = GameTimerDefaults.guessSeconds
  /// Cap on how many times each seat draws (host-settable). Actual draws are
  /// `min(maxRounds, playerCount)` so a 3-player game always draws three times.
  var maxRounds: Int = GameRoundDefaults.maxRounds
  /// Host-authored deadline for the current drawing/guessing turn.
  var phaseEndsAt: Date?
  /// Devices that dropped mid-round. Seats stay in `players` so pad indices
  /// stay stable; the engine auto-fills empty submissions for them each turn.
  var absentDeviceIds: Set<String> = []

  init(
    phase: GamePhase = .lobby,
    players: [Player] = [],
    hostId: String = "",
    roomId: String = "",
    networkHostDeviceId: String = "",
    stateEpoch: Int = 0,
    category: String = "",
    pads: [SketchPad] = [],
    turnIndex: Int = 0,
    submittedPlayerIds: Set<String> = [],
    revealPadIndex: Int = 0,
    revealStepIndex: Int = 0,
    drawTimeLimitSeconds: Int = GameTimerDefaults.drawSeconds,
    guessTimeLimitSeconds: Int = GameTimerDefaults.guessSeconds,
    maxRounds: Int = GameRoundDefaults.maxRounds,
    phaseEndsAt: Date? = nil,
    absentDeviceIds: Set<String> = []
  ) {
    self.phase = phase
    self.players = players
    self.hostId = hostId
    self.roomId = roomId
    self.networkHostDeviceId = networkHostDeviceId
    self.stateEpoch = stateEpoch
    self.category = category
    self.pads = pads
    self.turnIndex = turnIndex
    self.submittedPlayerIds = submittedPlayerIds
    self.revealPadIndex = revealPadIndex
    self.revealStepIndex = revealStepIndex
    self.drawTimeLimitSeconds = drawTimeLimitSeconds
    self.guessTimeLimitSeconds = guessTimeLimitSeconds
    self.maxRounds = maxRounds
    self.phaseEndsAt = phaseEndsAt
    self.absentDeviceIds = absentDeviceIds
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    phase = try container.decode(GamePhase.self, forKey: .phase)
    players = try container.decode([Player].self, forKey: .players)
    hostId = try container.decode(String.self, forKey: .hostId)
    roomId = try container.decodeIfPresent(String.self, forKey: .roomId) ?? ""
    networkHostDeviceId = try container.decodeIfPresent(String.self, forKey: .networkHostDeviceId) ?? ""
    stateEpoch = try container.decodeIfPresent(Int.self, forKey: .stateEpoch) ?? 0
    category = try container.decode(String.self, forKey: .category)
    pads = try container.decode([SketchPad].self, forKey: .pads)
    turnIndex = try container.decode(Int.self, forKey: .turnIndex)
    submittedPlayerIds = try container.decode(Set<String>.self, forKey: .submittedPlayerIds)
    revealPadIndex = try container.decode(Int.self, forKey: .revealPadIndex)
    revealStepIndex = try container.decodeIfPresent(Int.self, forKey: .revealStepIndex) ?? 0
    drawTimeLimitSeconds = try container.decodeIfPresent(Int.self, forKey: .drawTimeLimitSeconds)
      ?? GameTimerDefaults.drawSeconds
    guessTimeLimitSeconds = try container.decodeIfPresent(Int.self, forKey: .guessTimeLimitSeconds)
      ?? GameTimerDefaults.guessSeconds
    maxRounds = try container.decodeIfPresent(Int.self, forKey: .maxRounds)
      ?? GameRoundDefaults.maxRounds
    phaseEndsAt = try container.decodeIfPresent(Date.self, forKey: .phaseEndsAt)
    absentDeviceIds = try container.decodeIfPresent(Set<String>.self, forKey: .absentDeviceIds) ?? []
  }

  /// Mid-round sync payload without avatar ink (joiners already have them).
  func strippingAvatars() -> GameState {
    var copy = self
    copy.players = players.map { player in
      var next = player
      next.avatar = .empty
      return next
    }
    return copy
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

  /// How many times each seat will draw this round.
  /// Full game: once per pad (`players.count`). `maxRounds` caps that on big tables.
  var effectiveDrawCount: Int {
    guard !players.isEmpty else { return maxRounds }
    return min(maxRounds, players.count)
  }

  /// Total draw+guess turns before reveal: D G D G … D
  /// (= `2 * effectiveDrawCount - 1`) so every seat draws on every pad up to the cap.
  var effectiveTurnCount: Int {
    max(1, 2 * effectiveDrawCount - 1)
  }

  var isRoundComplete: Bool {
    !players.isEmpty && turnIndex >= effectiveTurnCount
  }

  var currentTurnTimeLimitSeconds: Int {
    isDrawTurn ? drawTimeLimitSeconds : guessTimeLimitSeconds
  }

  /// Drawing/guess steps on the pad currently being revealed (excludes the category prompt).
  var currentRevealContributions: [ChainStep] {
    guard pads.indices.contains(revealPadIndex) else { return [] }
    return pads[revealPadIndex].steps.filter {
      if case .prompt = $0 { return false }
      return true
    }
  }

  /// Contribution steps visible so far on the current reveal pad.
  var visibleRevealContributions: [ChainStep] {
    Array(currentRevealContributions.prefix(max(0, revealStepIndex)))
  }

  /// True when the current pad's last contribution is showing and this is the last pad.
  var isRevealFinished: Bool {
    guard pads.indices.contains(revealPadIndex) else { return true }
    return revealPadIndex + 1 >= pads.count
      && revealStepIndex >= currentRevealContributions.count
  }
}
