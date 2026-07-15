import Foundation

/// Owns refresh policy, stale-state, retry backoff, and last successful snapshot.
public actor QuotaRepository {
    private static let enrichmentCacheDuration: TimeInterval = 15 * 60

    public typealias RateLimitsFetcher = @Sendable () async throws -> WireGetAccountRateLimitsResponse
    public typealias ResetCreditsFetcher = @Sendable () async throws -> ResetCreditsDetail

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
    private let rateLimitsFetcher: RateLimitsFetcher?
    private let resetCreditsFetcher: ResetCreditsFetcher
    private var backoff = RetryBackoff()
    private var lastSuccess: QuotaSnapshot?
    private var refreshInFlight = false
    private var lastAttemptAt: Date?
    private var cachedResetCreditExpirations: [Date] = []
    private var lastEnrichmentSuccessAt: Date?
    private var enrichmentTask: Task<Void, Never>?

    public init(
        preferences: Preferences = .init(),
        creditsClient: ChatGPTQuotaClient = ChatGPTQuotaClient()
    ) {
        self.preferences = preferences
        self.rateLimitsFetcher = nil
        self.resetCreditsFetcher = { try await creditsClient.fetchResetCredits() }
    }

    /// Injectable boundary for deterministic repository tests without launching `codex` or HTTPS.
    public init(
        preferences: Preferences = .init(),
        rateLimitsFetcher: @escaping RateLimitsFetcher,
        resetCreditsFetcher: @escaping ResetCreditsFetcher
    ) {
        self.preferences = preferences
        self.rateLimitsFetcher = rateLimitsFetcher
        self.resetCreditsFetcher = resetCreditsFetcher
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
            let wire: WireGetAccountRateLimitsResponse
            if let rateLimitsFetcher {
                wire = try await rateLimitsFetcher()
            } else {
                let client = try await ensureClient()
                wire = try await client.readRateLimits()
            }
            var snapshot = RateLimitsMapper.snapshot(from: wire, fetchedAt: now, freshness: .current)
            // Prefer truthful empty-weekly state over inventing a short window.
            if snapshot.remainingPercent == nil {
                snapshot.statusMessage = "未返回本周额度窗口"
                snapshot.freshness = .current
            }
            if !cachedResetCreditExpirations.isEmpty {
                snapshot = RateLimitsMapper.merging(
                    snapshot,
                    resetCredits: ResetCreditsDetail(expiresAt: cachedResetCreditExpirations)
                )
            }
            lastSuccess = snapshot
            backoff.registerSuccess()
            startEnrichmentIfNeeded(now: now)
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
        enrichmentTask?.cancel()
        enrichmentTask = nil
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

    private func startEnrichmentIfNeeded(now: Date) {
        guard enrichmentTask == nil else { return }
        if let lastEnrichmentSuccessAt,
           now.timeIntervalSince(lastEnrichmentSuccessAt) < Self.enrichmentCacheDuration {
            return
        }

        let resetCreditsFetcher = self.resetCreditsFetcher
        enrichmentTask = Task { [weak self] in
            do {
                let detail = try await resetCreditsFetcher()
                await self?.finishEnrichment(detail, succeededAt: now)
            } catch {
                await self?.finishEnrichment(nil, succeededAt: nil)
            }
        }
    }

    private func finishEnrichment(_ detail: ResetCreditsDetail?, succeededAt: Date?) {
        defer { enrichmentTask = nil }
        guard let detail, let succeededAt else { return }

        lastEnrichmentSuccessAt = succeededAt
        cachedResetCreditExpirations = detail.expiresAt.sorted()
        guard let lastSuccess else { return }
        self.lastSuccess = RateLimitsMapper.merging(
            lastSuccess,
            resetCredits: ResetCreditsDetail(expiresAt: cachedResetCreditExpirations)
        )
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
