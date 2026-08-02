import Foundation

/// Local pass-the-phone handoff before a seat acts privately.
struct SeatHandoff: Equatable, Sendable {
  let playerId: String
  let title: String
  let message: String
}
