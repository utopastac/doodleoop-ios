import Foundation
import CryptoKit

/// A completed round kept on this device so everyone can re-read the drawing books.
struct SavedGame: Identifiable, Codable, Equatable {
  let id: UUID
  let completedAt: Date
  let category: String
  let players: [Player]
  let pads: [SketchPad]
  /// Stable fingerprint of pad content — used to avoid duplicate saves of the same round.
  let contentKey: String

  init(
    id: UUID = UUID(),
    completedAt: Date = Date(),
    category: String,
    players: [Player],
    pads: [SketchPad],
    contentKey: String
  ) {
    self.id = id
    self.completedAt = completedAt
    self.category = category
    self.players = players
    self.pads = pads
    self.contentKey = contentKey
  }

  init?(from state: GameState, completedAt: Date = Date()) {
    guard state.phase == .roundOver, !state.pads.isEmpty else { return nil }
    let key = Self.makeContentKey(category: state.category, players: state.players, pads: state.pads)
    self.init(
      completedAt: completedAt,
      category: state.category,
      players: state.players,
      pads: state.pads,
      contentKey: key
    )
  }

  func player(id: String) -> Player? {
    players.first { $0.id == id }
  }

  var playerNamesSummary: String {
    players.map(\.name).joined(separator: ", ")
  }

  static func makeContentKey(category: String, players: [Player], pads: [SketchPad]) -> String {
    struct Snapshot: Encodable {
      let category: String
      let players: [String]
      let pads: [SketchPad]
    }
    let snapshot = Snapshot(
      category: category,
      players: players.map { "\($0.id):\($0.name)" },
      pads: pads
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(snapshot) else {
      return UUID().uuidString
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
