import Foundation

/// Minimal seat shared by local party games. Game-specific profile fields live in each app.
public struct SeatPlayer: Identifiable, Codable, Equatable, Sendable {
  public let id: String
  /// Phone that owns this seat. Multiple seats may share one device.
  public var deviceId: String
  public var name: String

  public init(id: String, deviceId: String, name: String) {
    self.id = id
    self.deviceId = deviceId
    self.name = name
  }
}

/// Local pass-the-phone handoff before a seat acts privately.
public struct SeatHandoff: Equatable, Sendable {
  public let playerId: String
  public let title: String
  public let message: String

  public init(playerId: String, title: String, message: String) {
    self.playerId = playerId
    self.title = title
    self.message = message
  }
}
