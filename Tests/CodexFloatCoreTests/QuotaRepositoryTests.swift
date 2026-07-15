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
