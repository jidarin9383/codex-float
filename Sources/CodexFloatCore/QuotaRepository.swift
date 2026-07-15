import Foundation

/// Owns refresh policy, stale-state, retry backoff, and last successful snapshot.
public actor QuotaRepository {
    public struct Preferences: Sendable {
        public var executableOverride: URL?
        public var staleThreshold: TimeInterval
        public var widgetVisibleInterval: TimeInterval
        public var menuBarOnlyInterval: TimeInterval

        public init(
            executableOverride: URL? = nil,
            staleThreshold: TimeInterval = 30 * 60,
            widgetVisibleInterval: TimeInterval = 60,
            menuBarOnlyInterval: TimeInterval = 60
        ) {
            self.executableOverride = executableOverride
            self.staleThreshold = staleThreshold
            self.widgetVisibleInterval = widgetVisibleInterval
            self.menuBarOnlyInterval = menuBarOnlyInterval
        }
    }

    public enum SurfaceMode: Sendable {
        case menuBarOnly
        case widgetVisible
    }

    private var preferences: Preferences
    private var client: CodexAppServerClient?
    private let creditsClient: ChatGPTQuotaClient
    private var backoff = RetryBackoff()
    private var lastSuccess: QuotaSnapshot?
    private var refreshInFlight = false
    private var lastAttemptAt: Date?

    public init(
        preferences: Preferences = .init(),
        creditsClient: ChatGPTQuotaClient = ChatGPTQuotaClient()
    ) {
        self.preferences = preferences
        self.creditsClient = creditsClient
    }

    public func updatePreferences(_ preferences: Preferences) {
        self.preferences = preferences
    }

    public func lastSuccessfulSnapshot() -> QuotaSnapshot? {
        lastSuccess
    }

    public func nextDelay(after failure: Bool = false) -> TimeInterval {
        if failure {
            return backoff.delay
        }
        return 0
    }

    public func recommendedPollingInterval(mode: SurfaceMode) -> TimeInterval {
        switch mode {
        case .menuBarOnly:
            return preferences.menuBarOnlyInterval
        case .widgetVisible:
            return preferences.widgetVisibleInterval
        }
    }

    /// Sleep until the next refresh: failure backoff when unhealthy, else surface cadence.
    public func nextPollingDelay(mode: SurfaceMode) -> TimeInterval {
        if backoff.failureCount > 0 {
            return max(backoff.delay, 1)
        }
        return recommendedPollingInterval(mode: mode)
    }

    public var consecutiveFailureCount: Int {
        backoff.failureCount
    }

    /// Fetch a fresh snapshot. Concurrent callers share one in-flight request.
    @discardableResult
    public func refresh(now: Date = .now) async -> QuotaSnapshot {
        if refreshInFlight {
            // Waiters still get the last known view; caller can re-enter after.
            if var last = lastSuccess {
                if RateLimitsMapper.isStale(
                    fetchedAt: last.fetchedAt,
                    now: now,
                    threshold: preferences.staleThreshold
                ) {
                    last.freshness = .stale
                    if last.statusMessage == nil {
                        last.statusMessage = "数据可能不是最新"
                    }
                }
                return last
            }
            return QuotaSnapshot(freshness: .loading, statusMessage: "正在读取额度…")
        }

        refreshInFlight = true
        defer { refreshInFlight = false }
        lastAttemptAt = now

        do {
            let client = try await ensureClient()
            let wire = try await client.readRateLimits()
            var snapshot = RateLimitsMapper.snapshot(from: wire, fetchedAt: now, freshness: .current)
            // Prefer truthful empty-weekly state over inventing a short window.
            if snapshot.remainingPercent == nil {
                snapshot.statusMessage = "未返回本周额度窗口"
                snapshot.freshness = .current
            }
            // Enrich reset opportunities with per-credit expiry when auth + HTTPS succeed.
            // Failures are non-fatal: keep app-server count-only rows.
            if let detail = try? await creditsClient.fetchResetCredits() {
                snapshot = RateLimitsMapper.merging(snapshot, resetCredits: detail)
            }
            lastSuccess = snapshot
            backoff.registerSuccess()
            return snapshot
        } catch let error as AppServerClientError {
            // Drop dead process so the next attempt relaunches cleanly.
            switch error {
            case .processExited, .notRunning, .timeout, .ioFailure:
                await client?.shutdown()
                client = nil
            default:
                break
            }
            backoff.registerFailure()
            return failureSnapshot(error: error, now: now)
        } catch {
            await client?.shutdown()
            client = nil
            backoff.registerFailure()
            return failureSnapshot(
                error: .ioFailure(error.localizedDescription),
                now: now
            )
        }
    }

    /// Apply optional stale marking to a retained success without fetching.
    public func reevaluateFreshness(now: Date = .now) -> QuotaSnapshot? {
        guard var last = lastSuccess else { return nil }
        if RateLimitsMapper.isStale(
            fetchedAt: last.fetchedAt,
            now: now,
            threshold: preferences.staleThreshold
        ), last.freshness == .current {
            last.freshness = .stale
            last.statusMessage = "数据可能不是最新"
            lastSuccess = last
        }
        return lastSuccess
    }

    public func shutdown() async {
        await client?.shutdown()
        client = nil
    }

    // MARK: - Private

    private func ensureClient() async throws -> CodexAppServerClient {
        if let client {
            return client
        }
        guard let url = CodexExecutableLocator.resolve(override: preferences.executableOverride) else {
            throw AppServerClientError.executableNotFound
        }
        let created = CodexAppServerClient(executableURL: url)
        self.client = created
        return created
    }

    private func failureSnapshot(error: AppServerClientError, now: Date) -> QuotaSnapshot {
        if var last = lastSuccess {
            last.freshness = .stale
            last.statusMessage = error.uiMessage
            // Keep last numbers but mark untrustworthy.
            return last
        }
        return QuotaSnapshot(
            fetchedAt: now,
            freshness: .error,
            statusMessage: error.uiMessage
        )
    }
}
