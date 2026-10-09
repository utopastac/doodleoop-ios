import Foundation

/// Cancels and replaces a named wait before a disconnect is treated as final.
@MainActor
final class DisconnectGrace {
  var seconds: TimeInterval = 15

  private var tasks: [String: Task<Void, Never>] = [:]

  func schedule(key: String, action: @escaping @MainActor () -> Void) {
    tasks[key]?.cancel()
    let seconds = seconds
    tasks[key] = Task { [weak self] in
      let ns = UInt64(max(0, seconds) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: ns)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        self?.tasks[key] = nil
        action()
      }
    }
  }

  func cancel(key: String) {
    tasks[key]?.cancel()
    tasks[key] = nil
  }

  func cancelAll() {
    for task in tasks.values {
      task.cancel()
    }
    tasks.removeAll()
  }
}
