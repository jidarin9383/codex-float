import XCTest
@testable import CodexFloatCore

final class QuotaRepositoryTests: XCTestCase {
    func testRefreshReturnsBeforeHTTPSCompletion() async throws {
        let expiry = testExpiry
        let gate = EnrichmentGate()
        let repository = makeRepository {
            try await gate.fetch()
        }

        let snapshot = await repository.refresh(now: testNow)

        XCTAssertEqual(snapshot.remainingPercent, 18)
        XCTAssertEqual(snapshot.resetOpportunityCount, 1)
        XCTAssertNil(snapshot.resetOpportunities.first?.expiresAt)
        try await waitUntil { await gate.callCount == 1 }

        await gate.resolve(with: ResetCreditsDetail(expiresAt: [expiry]))
        try await waitUntil {
            await repository.lastSuccessfulSnapshot()?.resetOpportunities.first?.expiresAt == expiry
        }
        await repository.shutdown()
    }

    func testFailedEnrichmentRetriesOnNextRefresh() async throws {
        let expiry = testExpiry
        let fetcher = SequencedEnrichmentFetcher(results: [
            .failure(ChatGPTQuotaClientError.network),
            .success(ResetCreditsDetail(expiresAt: [expiry]))
        ])
        let repository = makeRepository { try await fetcher.fetch() }

        _ = await repository.refresh(now: testNow)
        try await waitUntil { await fetcher.callCount == 1 }

        _ = await repository.refresh(now: testNow.addingTimeInterval(60))
        try await waitUntil { await fetcher.callCount == 2 }
        try await waitUntil {
            await repository.lastSuccessfulSnapshot()?.resetOpportunities.first?.expiresAt == expiry
        }
        await repository.shutdown()
    }

    func testSuccessfulEnrichmentIsCachedForFifteenMinutes() async throws {
        let expiry = testExpiry
        let fetcher = SequencedEnrichmentFetcher(results: [
            .success(ResetCreditsDetail(expiresAt: [expiry])),
            .success(ResetCreditsDetail(expiresAt: [expiry]))
        ])
        let repository = makeRepository { try await fetcher.fetch() }

        _ = await repository.refresh(now: testNow)
        try await waitUntil { await fetcher.callCount == 1 }
        try await waitUntil {
            await repository.lastSuccessfulSnapshot()?.resetOpportunities.first?.expiresAt == expiry
        }

        _ = await repository.refresh(now: testNow.addingTimeInterval(899))
        await Task.yield()
        let cachedCallCount = await fetcher.callCount
        XCTAssertEqual(cachedCallCount, 1)

        _ = await repository.refresh(now: testNow.addingTimeInterval(900))
        try await waitUntil { await fetcher.callCount == 2 }
        await repository.shutdown()
    }

    func testPlusEnrichmentPromotesFiveHourGlance() async throws {
        let fiveHour = QuotaWindow(
            id: "five-hour",
            remainingPercent: 60,
            usedPercent: 40,
            windowDurationMins: 300,
            resetsAt: testNow.addingTimeInterval(3 * 3600),
            isFiveHour: true
        )
        let gate = EnrichmentGate()
        let repository = QuotaRepository(
            rateLimitsFetcher: {
                WireGetAccountRateLimitsResponse(
                    rateLimits: WireRateLimitSnapshot(
                        planType: "plus",
                        primary: WireRateLimitWindow(
                            usedPercent: 82,
                            windowDurationMins: 10_080,
                            resetsAt: 1_800_000_000
                        )
                    ),
                    rateLimitResetCredits: WireRateLimitResetCredits(availableCount: 1)
                )
            },
            resetCreditsFetcher: { try await gate.fetch() }
        )

        let snapshot = await repository.refresh(now: testNow)
        XCTAssertEqual(snapshot.remainingPercent, 18)
        XCTAssertFalse(snapshot.usesFiveHourGlance)
        try await waitUntil { await gate.callCount == 1 }

        await gate.resolve(with: ResetCreditsDetail(expiresAt: [testExpiry], fiveHourWindow: fiveHour))
        try await waitUntil {
            await repository.lastSuccessfulSnapshot()?.remainingPercent == 60
        }
        let enriched = await repository.lastSuccessfulSnapshot()
        XCTAssertEqual(enriched?.remainingPercent, 60)
        XCTAssertEqual(enriched?.usesFiveHourGlance, true)
        await repository.shutdown()
    }

    func testConcurrentRefreshWaitsForFreshResult() async throws {
        let gate = RateLimitsGate()
        let repository = QuotaRepository(
            rateLimitsFetcher: { await gate.fetch() },
            resetCreditsFetcher: { throw ChatGPTQuotaClientError.network }
        )
        let now = testNow
        let first = Task { await repository.refresh(now: now) }
        try await waitUntil { await gate.callCount == 1 }
        let second = Task { await repository.refresh(now: now) }
        try await Task.sleep(for: .milliseconds(20))
        await gate.resolve()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult.remainingPercent, 18)
        XCTAssertEqual(secondResult, firstResult)
        let calls = await gate.callCount
        XCTAssertEqual(calls, 1)
        await repository.shutdown()
    }

    func testManualRefreshFollowsInFlightAutomaticRead() async throws {
        let gate = RateLimitsGate()
        let repository = QuotaRepository(
            rateLimitsFetcher: { await gate.fetch() },
            resetCreditsFetcher: { throw ChatGPTQuotaClientError.network }
        )
        let now = testNow
        let automatic = Task { await repository.refresh(now: now) }
        try await waitUntil { await gate.callCount == 1 }
        let manual = Task { await repository.refresh(now: now.addingTimeInterval(1), force: true) }
        try await Task.sleep(for: .milliseconds(20))
        await gate.resolve()
        _ = await automatic.value
        let result = await manual.value
        XCTAssertEqual(result.fetchedAt, now.addingTimeInterval(1))
        XCTAssertEqual(result.remainingPercent, 18)
        let calls = await gate.callCount
        XCTAssertEqual(calls, 2)
        await repository.shutdown()
    }

    func testConcurrentManualRefreshesShareOneRequest() async throws {
        let gate = RateLimitsGate()
        let repository = QuotaRepository(
            rateLimitsFetcher: { await gate.fetch() },
            resetCreditsFetcher: { throw ChatGPTQuotaClientError.network }
        )
        let now = testNow
        let first = Task { await repository.refresh(now: now, force: true) }
        try await waitUntil { await gate.callCount == 1 }
        let second = Task { await repository.refresh(now: now, force: true) }
        try await Task.sleep(for: .milliseconds(20))
        await gate.resolve()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, secondResult)
        let calls = await gate.callCount
        XCTAssertEqual(calls, 1)
        await repository.shutdown()
    }

    func testManualRefreshBypassesCacheAndAwaitsEnrichment() async throws {
        let expiry = testExpiry
        let fetcher = SequencedEnrichmentFetcher(results: [
            .success(ResetCreditsDetail(expiresAt: [testExpiry])),
            .success(ResetCreditsDetail(expiresAt: [testExpiry.addingTimeInterval(3600)])),
            .failure(ChatGPTQuotaClientError.network)
        ])
        let repository = makeRepository { try await fetcher.fetch() }
        _ = await repository.refresh(now: testNow)
        try await waitUntil {
            await repository.lastSuccessfulSnapshot()?.resetOpportunities.first?.expiresAt == expiry
        }
        let forced = await repository.refresh(now: testNow.addingTimeInterval(1), force: true)
        XCTAssertEqual(forced.resetOpportunities.first?.expiresAt, testExpiry.addingTimeInterval(3600))
        let calls = await fetcher.callCount
        XCTAssertEqual(calls, 2)
        let fallback = await repository.refresh(now: testNow.addingTimeInterval(2), force: true)
        XCTAssertEqual(fallback.remainingPercent, 18)
        XCTAssertEqual(fallback.freshness, .current)
        await repository.shutdown()
    }

    func testManualRefreshReplacesCachedPlusFiveHourWindow() async throws {
        let now = testNow
        let initial = QuotaWindow(
            id: "five-hour", remainingPercent: 60, usedPercent: 40,
            windowDurationMins: 300, resetsAt: now.addingTimeInterval(3600), isFiveHour: true
        )
        var updated = initial
        updated.remainingPercent = 45
        updated.usedPercent = 55
        let fetcher = SequencedEnrichmentFetcher(results: [
            .success(ResetCreditsDetail(expiresAt: [], fiveHourWindow: initial)),
            .success(ResetCreditsDetail(expiresAt: [], fiveHourWindow: updated)),
            .failure(ChatGPTQuotaClientError.network)
        ])
        let repository = QuotaRepository(
            rateLimitsFetcher: {
                WireGetAccountRateLimitsResponse(rateLimits: WireRateLimitSnapshot(
                    planType: "plus",
                    primary: WireRateLimitWindow(
                        usedPercent: 82, windowDurationMins: 10_080, resetsAt: 1_800_000_000
                    )
                ))
            },
            resetCreditsFetcher: { try await fetcher.fetch() }
        )
        _ = await repository.refresh(now: now)
        try await waitUntil { await repository.lastSuccessfulSnapshot()?.remainingPercent == 60 }
        let forced = await repository.refresh(now: now.addingTimeInterval(1), force: true)
        XCTAssertEqual(forced.remainingPercent, 45)
        XCTAssertTrue(forced.usesFiveHourGlance)
        let fallback = await repository.refresh(now: now.addingTimeInterval(2), force: true)
        XCTAssertEqual(fallback.remainingPercent, 18)
        XCTAssertFalse(fallback.usesFiveHourGlance)
        await repository.shutdown()
    }

    func testAutomaticEnrichmentReplacesPreviousHTTPSWindow() async throws {
        let initial = QuotaWindow(
            id: "five-hour", remainingPercent: 60, usedPercent: 40,
            windowDurationMins: 300, isFiveHour: true
        )
        var updated = initial
        updated.remainingPercent = 45
        updated.usedPercent = 55
        let expiry = testExpiry.addingTimeInterval(3600)
        let fetcher = SequencedEnrichmentFetcher(results: [
            .success(ResetCreditsDetail(expiresAt: [testExpiry], fiveHourWindow: initial)),
            .success(ResetCreditsDetail(expiresAt: [expiry], fiveHourWindow: updated))
        ])
        let repository = makePlusRepository { try await fetcher.fetch() }
        _ = await repository.refresh(now: testNow)
        try await waitUntil { await repository.lastSuccessfulSnapshot()?.remainingPercent == 60 }
        _ = await repository.refresh(now: testNow.addingTimeInterval(900))
        try await waitUntil {
            await repository.lastSuccessfulSnapshot()?.resetOpportunities.first?.expiresAt == expiry
        }
        let result = await repository.lastSuccessfulSnapshot()
        XCTAssertEqual(result?.remainingPercent, 45)
        XCTAssertEqual(result?.weeklyWindow?.remainingPercent, 18)
        await repository.shutdown()
    }

    private func makePlusRepository(
        resetCreditsFetcher: @escaping QuotaRepository.ResetCreditsFetcher
    ) -> QuotaRepository {
        QuotaRepository(
            rateLimitsFetcher: {
                WireGetAccountRateLimitsResponse(
                    rateLimits: WireRateLimitSnapshot(
                        planType: "plus",
                        primary: WireRateLimitWindow(usedPercent: 82, windowDurationMins: 10_080)
                    ),
                    rateLimitResetCredits: WireRateLimitResetCredits(availableCount: 1)
                )
            },
            resetCreditsFetcher: resetCreditsFetcher
        )
    }

    func testEnrichmentPublishesWithoutAnotherRefresh() async throws {
        let gate = EnrichmentGate()
        let repository = makePlusRepository { try await gate.fetch() }
        var updates = await repository.snapshotUpdates().makeAsyncIterator()
        _ = await repository.refresh(now: testNow)
        let initial = await updates.next()
        XCTAssertEqual(initial?.remainingPercent, 18)
        try await waitUntil { await gate.callCount == 1 }
        await gate.resolve(with: ResetCreditsDetail(
            expiresAt: [], fiveHourWindow: QuotaWindow(
                id: "five-hour", remainingPercent: 60, usedPercent: 40,
                windowDurationMins: 300, isFiveHour: true
            )
        ))
        try await waitUntil { await repository.lastSuccessfulSnapshot()?.remainingPercent == 60 }
        let enriched = await updates.next()
        XCTAssertEqual(enriched?.remainingPercent, 60)
        XCTAssertTrue(enriched?.usesFiveHourGlance == true)
        await repository.shutdown()
    }

    func testCancelledObservationCanSubscribeAgain() async throws {
        let repository = makeRepository { throw ChatGPTQuotaClientError.network }
        let updates = await repository.snapshotUpdates()
        let observer = Task {
            for await _ in updates {}
        }
        observer.cancel()
        await observer.value
        _ = await repository.refresh(now: testNow)
        var replacement = await repository.snapshotUpdates().makeAsyncIterator()
        let snapshot = await replacement.next()
        XCTAssertEqual(snapshot?.remainingPercent, 18)
        await repository.shutdown()
    }

    func testSuccessfulUsageWithoutFiveHourClearsPreviousHTTPSWindow() async throws {
        let expiry = testExpiry.addingTimeInterval(3600)
        let fetcher = SequencedEnrichmentFetcher(results: [
            .success(ResetCreditsDetail(expiresAt: [testExpiry], fiveHourWindow: QuotaWindow(
                id: "five-hour", remainingPercent: 60, usedPercent: 40,
                windowDurationMins: 300, isFiveHour: true
            ))),
            .success(ResetCreditsDetail(expiresAt: [expiry]))
        ])
        let repository = makePlusRepository { try await fetcher.fetch() }
        _ = await repository.refresh(now: testNow)
        try await waitUntil { await repository.lastSuccessfulSnapshot()?.remainingPercent == 60 }
        _ = await repository.refresh(now: testNow.addingTimeInterval(900))
        try await waitUntil {
            await repository.lastSuccessfulSnapshot()?.resetOpportunities.first?.expiresAt == expiry
        }
        let result = await repository.lastSuccessfulSnapshot()
        XCTAssertFalse(result?.usesFiveHourGlance == true)
        XCTAssertEqual(result?.remainingPercent, 18)
        XCTAssertEqual(result?.freshness, .current)
        await repository.shutdown()
    }

    func testAppServerFiveHourWinsOverHTTPSDuringManualRefresh() async throws {
        let repository = QuotaRepository(
            rateLimitsFetcher: {
                WireGetAccountRateLimitsResponse(rateLimits: .init(
                    planType: "plus", primary: .init(usedPercent: 40, windowDurationMins: 300),
                    secondary: .init(usedPercent: 82, windowDurationMins: 10_080)
                ))
            },
            resetCreditsFetcher: {
                ResetCreditsDetail(expiresAt: [], fiveHourWindow: QuotaWindow(
                    id: "five-hour", remainingPercent: 45, usedPercent: 55,
                    windowDurationMins: 300, isFiveHour: true
                ))
            }
        )
        let result = await repository.refresh(now: testNow, force: true)
        XCTAssertEqual(result.remainingPercent, 60)
        XCTAssertEqual(result.weeklyWindow?.remainingPercent, 18)
        await repository.shutdown()
    }

    private let testNow = Date(timeIntervalSince1970: 1_800_000_000)
    private let testExpiry = Date(timeIntervalSince1970: 1_800_086_400)

    private func makeRepository(
        resetCreditsFetcher: @escaping QuotaRepository.ResetCreditsFetcher
    ) -> QuotaRepository {
        QuotaRepository(
            rateLimitsFetcher: {
                WireGetAccountRateLimitsResponse(
                    rateLimits: WireRateLimitSnapshot(
                        primary: WireRateLimitWindow(
                            usedPercent: 82,
                            windowDurationMins: 10_080,
                            resetsAt: 1_800_000_000
                        )
                    ),
                    rateLimitResetCredits: WireRateLimitResetCredits(availableCount: 1)
                )
            },
            resetCreditsFetcher: resetCreditsFetcher
        )
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for asynchronous repository state")
    }
}

private actor EnrichmentGate {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<ResetCreditsDetail, Error>?

    func fetch() async throws -> ResetCreditsDetail {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(with detail: ResetCreditsDetail) {
        continuation?.resume(returning: detail)
        continuation = nil
    }
}

private actor SequencedEnrichmentFetcher {
    private var results: [Result<ResetCreditsDetail, Error>]
    private(set) var callCount = 0

    init(results: [Result<ResetCreditsDetail, Error>]) {
        self.results = results
    }

    func fetch() throws -> ResetCreditsDetail {
        callCount += 1
        return try results.removeFirst().get()
    }
}

private actor RateLimitsGate {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<WireGetAccountRateLimitsResponse, Never>?
    private var result: WireGetAccountRateLimitsResponse?

    func fetch() async -> WireGetAccountRateLimitsResponse {
        callCount += 1
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve() {
        let wire = WireGetAccountRateLimitsResponse(
            rateLimits: WireRateLimitSnapshot(primary: WireRateLimitWindow(
                usedPercent: 82, windowDurationMins: 10_080, resetsAt: 1_800_000_000
            ))
        )
        result = wire
        continuation?.resume(returning: wire)
        continuation = nil
    }
}
