import Foundation

/// Owns refresh policy, stale-state, retry backoff, and last successful snapshot.
public actor QuotaRepository {
    private static let enrichmentCacheDuration: TimeInterval = 15 * 60
    private var snapshotObservers: [UUID: AsyncStream<QuotaSnapshot>.Continuation] = [:]
    private var lastPublishedSnapshot: QuotaSnapshot?

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
    private var lastAppServerSnapshot: QuotaSnapshot?
    private var refreshTask: Task<QuotaSnapshot, Never>?
    private var refreshIsForced = false
    private var lastAttemptAt: Date?
    private var cachedResetCreditExpirations: [Date] = []
    private var cachedFiveHourWindow: QuotaWindow?
    private var cachedFiveHourFetchedAt: Date?
    private var usageEnrichmentFailed = false
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

    deinit {
        for observer in snapshotObservers.values { observer.finish() }
    }

    /// Ordered updates include background enrichment; a cancelled surface can subscribe again.
    public func snapshotUpdates() -> AsyncStream<QuotaSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<QuotaSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        snapshotObservers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSnapshotObserver(id) }
        }
        if let lastPublishedSnapshot { continuation.yield(lastPublishedSnapshot) }
        return stream
    }

    private func removeSnapshotObserver(_ id: UUID) {
        snapshotObservers.removeValue(forKey: id)
    }

    private func publish(_ snapshot: QuotaSnapshot) {
        lastPublishedSnapshot = snapshot
        for observer in snapshotObservers.values { observer.yield(snapshot) }
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

    /// Concurrent callers await a shared result; manual recovery follows any ordinary read.
    @discardableResult
    public func refresh(now: Date = .now, force: Bool = false) async -> QuotaSnapshot {
        if let refreshTask {
            let wasForced = refreshIsForced
            let result = await refreshTask.value
            if !force || wasForced { return result }
            return await refresh(now: now, force: true)
        }
        refreshIsForced = force
        let task = Task { await self.performRefresh(now: now, force: force) }
        refreshTask = task
        return await task.value
    }

    private func performRefresh(now: Date, force: Bool) async -> QuotaSnapshot {
        defer {
            refreshTask = nil
            refreshIsForced = false
        }
        if force {
            // A fresh process also recovers reads that succeed with an old server snapshot.
            await client?.shutdown()
            client = nil
            // Let a prior enrichment finish before bypassing its cache.
            await enrichmentTask?.value
            cachedFiveHourWindow = nil
            cachedFiveHourFetchedAt = nil
            usageEnrichmentFailed = false
            lastEnrichmentSuccessAt = nil
        }
        lastAttemptAt = now

        do {
            let wire: WireGetAccountRateLimitsResponse
            if let rateLimitsFetcher {
                wire = try await rateLimitsFetcher()
            } else {
                do {
                    let client = try await ensureClient()
                    wire = try await client.readRateLimits()
                } catch let error as AppServerClientError {
                    guard case .protocolError = error else { throw error }
                    await client?.shutdown()
                    client = nil
                    let replacement = try await ensureClient()
                    wire = try await replacement.readRateLimits()
                }
            }
            var snapshot = RateLimitsMapper.snapshot(from: wire, fetchedAt: now, freshness: .current)
            lastAppServerSnapshot = snapshot
            snapshot = enrichedSnapshot() ?? snapshot
            // Prefer truthful empty glance state over inventing a short window.
            if snapshot.remainingPercent == nil {
                snapshot.statusMessage = snapshot.isPlusPlan ? "未返回额度窗口" : "未返回本周额度窗口"
                snapshot.freshness = .current
            }
            lastSuccess = snapshot
            backoff.registerSuccess()
            if force {
                do {
                    let detail = try await resetCreditsFetcher()
                    finishEnrichment(detail, succeededAt: now)
                } catch {
                    // HTTPS is optional; the fresh app-server snapshot remains authoritative.
                    finishEnrichment(nil, succeededAt: nil)
                }
                publish(lastSuccess ?? snapshot)
                return lastSuccess ?? snapshot
            }
            publish(snapshot)
            startEnrichmentIfNeeded(now: now)
            return snapshot
        } catch let error as AppServerClientError {
            // Drop dead process so the next attempt relaunches cleanly.
            switch error {
            case .processExited, .notRunning, .timeout, .ioFailure, .protocolError:
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
            if let source = lastAppServerSnapshot,
               RateLimitsMapper.isStale(fetchedAt: source.fetchedAt, now: now, threshold: preferences.staleThreshold) {
                lastAppServerSnapshot?.freshness = .stale
                lastAppServerSnapshot?.statusMessage = last.statusMessage
            }
            publish(last)
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
        if let detail, let succeededAt {
            lastEnrichmentSuccessAt = detail.usageFetchSucceeded ? succeededAt : nil
            usageEnrichmentFailed = !detail.usageFetchSucceeded
            cachedResetCreditExpirations = detail.expiresAt.sorted()
            if detail.usageFetchSucceeded {
                // A successful usage response without a short window is a valid fallback state.
                cachedFiveHourWindow = detail.fiveHourWindow.flatMap { $0.isFiveHour ? $0 : nil }
                cachedFiveHourFetchedAt = cachedFiveHourWindow == nil ? nil : succeededAt
            }
        } else {
            lastEnrichmentSuccessAt = nil
            usageEnrichmentFailed = true
        }
        guard let snapshot = enrichedSnapshot() else { return }
        lastSuccess = snapshot
        publish(snapshot)
    }

    private func enrichedSnapshot() -> QuotaSnapshot? {
        guard let source = lastAppServerSnapshot else { return nil }
        // Rebuild from the authoritative source, so a prior HTTPS window cannot block its replacement.
        var snapshot = RateLimitsMapper.merging(
            source,
            resetCredits: ResetCreditsDetail(
                expiresAt: cachedResetCreditExpirations,
                fiveHourWindow: cachedFiveHourWindow
            )
        )
        if source.isPlusPlan, source.fiveHourWindow == nil, cachedFiveHourWindow != nil {
            snapshot.fetchedAt = cachedFiveHourFetchedAt ?? source.fetchedAt
            if usageEnrichmentFailed, source.freshness == .current {
                snapshot.freshness = .stale
                snapshot.statusMessage = "5 小时额度更新失败，显示上次数据"
            }
        }
        if snapshot.remainingPercent == nil, snapshot.freshness == .current {
            snapshot.statusMessage = snapshot.isPlusPlan ? "未返回额度窗口" : "未返回本周额度窗口"
        }
        return snapshot
    }

    private func failureSnapshot(error: AppServerClientError, now: Date) -> QuotaSnapshot {
        if var last = lastSuccess {
            last.freshness = .stale
            last.statusMessage = error.uiMessage
            lastSuccess = last
            lastAppServerSnapshot?.freshness = .stale
            lastAppServerSnapshot?.statusMessage = error.uiMessage
            publish(last)
            // Keep last numbers but mark untrustworthy.
            return last
        }
        let snapshot = QuotaSnapshot(
            fetchedAt: now,
            freshness: .error,
            statusMessage: error.uiMessage
        )
        publish(snapshot)
        return snapshot
    }
}
