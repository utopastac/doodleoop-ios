import Foundation
import Observation

/// Local on-device archive of finished rounds (every phone saves its own copy).
@MainActor
@Observable
final class GameHistoryStore {
  private(set) var games: [SavedGame] = []

  private let directory: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private var knownContentKeys: Set<String> = []

  init(directory: URL? = nil) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder

    if let directory {
      self.directory = directory
    } else {
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      self.directory = base.appendingPathComponent("Doodleoop/History", isDirectory: true)
    }

    try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    reload()
  }

  /// Saves a completed round once. Returns the saved game, or `nil` if skipped / failed.
  @discardableResult
  func saveIfNeeded(from state: GameState, completedAt: Date = Date()) -> SavedGame? {
    guard let game = SavedGame(from: state, completedAt: completedAt) else { return nil }
    return save(game)
  }

  @discardableResult
  func save(_ game: SavedGame) -> SavedGame? {
    if knownContentKeys.contains(game.contentKey) { return nil }
    guard let data = try? encoder.encode(game) else { return nil }
    let url = fileURL(for: game.id)
    do {
      try data.write(to: url, options: [.atomic])
    } catch {
      return nil
    }
    knownContentKeys.insert(game.contentKey)
    games.insert(game, at: 0)
    return game
  }

  func delete(_ game: SavedGame) {
    try? FileManager.default.removeItem(at: fileURL(for: game.id))
    knownContentKeys.remove(game.contentKey)
    games.removeAll { $0.id == game.id }
  }

  func reload() {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )) ?? []

    var loaded: [SavedGame] = []
    var keys = Set<String>()
    for url in urls where url.pathExtension == "json" {
      guard let data = try? Data(contentsOf: url),
            let game = try? decoder.decode(SavedGame.self, from: data) else { continue }
      loaded.append(game)
      keys.insert(game.contentKey)
    }
    loaded.sort { $0.completedAt > $1.completedAt }
    games = loaded
    knownContentKeys = keys
  }

  private func fileURL(for id: UUID) -> URL {
    directory.appendingPathComponent("\(id.uuidString).json")
  }
}
