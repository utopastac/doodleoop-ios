import Foundation

/// User-facing explanation when Multipeer play can't continue or join fails.
struct SessionAlert: Equatable, Identifiable {
  enum Kind: String, Equatable {
    case hostEndedGame
    case lostConnection
    case joinFailed
    case localNetwork
  }

  let kind: Kind
  let title: String
  let message: String

  var id: String { kind.rawValue }

  static let hostEndedGame = SessionAlert(
    kind: .hostEndedGame,
    title: "Game ended",
    message: "The host ended this game."
  )

  static let lostConnection = SessionAlert(
    kind: .lostConnection,
    title: "Connection lost",
    message: "Lost connection to the host. Make sure everyone is nearby with Local Network turned on for Doodleoop."
  )

  static func joinFailed(peerName: String) -> SessionAlert {
    SessionAlert(
      kind: .joinFailed,
      title: "Couldn't join",
      message: "Couldn't reach \(peerName). Stay nearby, accept Local Network access, and try again."
    )
  }

  static func localNetwork(message: String) -> SessionAlert {
    SessionAlert(
      kind: .localNetwork,
      title: "Can't find nearby phones",
      message: message
    )
  }
}

/// Joiner Multipeer browse / invite lifecycle.
enum JoinStatus: Equatable {
  case idle
  case browsing
  case connecting(to: String)
  case failed(message: String)
}
