import Foundation

/// Shared wait-until-phase-end timing for drawing and guessing auto-submit.
enum PhaseTimer {
  /// Sleeps until `endsAt`, then returns false if the task was cancelled.
  static func waitForExpiry(endsAt: Date?) async -> Bool {
    guard let endsAt else { return false }
    let delay = endsAt.timeIntervalSinceNow
    if delay > 0 {
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    return !Task.isCancelled
  }
}
