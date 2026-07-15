import Foundation

/// Failure backoff schedule from Tech-Spec: 15s, 30s, 1m, then 5m capped.
public struct RetryBackoff: Equatable, Sendable {
    public static let schedule: [TimeInterval] = [15, 30, 60, 300]

    public private(set) var failureCount: Int

    public init(failureCount: Int = 0) {
        self.failureCount = max(0, failureCount)
    }

    public var delay: TimeInterval {
        guard failureCount > 0 else { return 0 }
        let index = min(failureCount - 1, Self.schedule.count - 1)
        return Self.schedule[index]
    }

    public mutating func registerSuccess() {
        failureCount = 0
    }

    public mutating func registerFailure() {
        failureCount += 1
    }
}
