import Foundation
import XCTest
@testable import CodexFloatCore

final class QuotaNetworkRecoveryTests: XCTestCase {
    func testPartialUsageFailureRetriesAfterConnectionReturns() async throws {
        let state = QuotaNetworkProtocol.state
        state.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.protocolClasses = [QuotaNetworkProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = ChatGPTQuotaClient(session: session)
        let repository = QuotaRepository(
            rateLimitsFetcher: {
                WireGetAccountRateLimitsResponse(
                    rateLimits: .init(planType: "plus", primary: .init(usedPercent: 82, windowDurationMins: 10_080)),
                    rateLimitResetCredits: .init(availableCount: 1)
                )
            },
            resetCreditsFetcher: {
                try await client.fetchResetCredits(session: .init(accessToken: "test-fixture-only"))
            }
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = await repository.refresh(now: now)
        try await waitUntil { await repository.lastSuccessfulSnapshot()?.remainingPercent == 60 }

        state.setUsageOffline(true)
        _ = await repository.refresh(now: now.addingTimeInterval(900))
        // The changed credit date confirms the partial response has been applied.
        try await waitUntil {
            await repository.lastSuccessfulSnapshot()?.resetOpportunities.first?.expiresAt
                == Date(timeIntervalSince1970: 1_800_007_200)
        }
        let stale = await repository.lastSuccessfulSnapshot()
        XCTAssertEqual(stale?.freshness, .stale)
        XCTAssertEqual(stale?.remainingPercent, 60)

        state.setUsageOffline(false)
        _ = await repository.refresh(now: now.addingTimeInterval(960))
        try await waitUntil { state.usageRequests == 3 }
        try await waitUntil { await repository.lastSuccessfulSnapshot()?.remainingPercent == 45 }
        let recovered = await repository.lastSuccessfulSnapshot()
        XCTAssertEqual(recovered?.freshness, .current)
        await repository.shutdown()
    }

    private func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for quota recovery")
    }
}

private final class QuotaNetworkFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var offline = false
    private var calls = 0
    var usageRequests: Int { lock.withLock { calls } }
    func setUsageOffline(_ value: Bool) { lock.withLock { offline = value } }
    func reset() { lock.withLock { offline = false; calls = 0 } }

    func response(isUsage: Bool) throws -> Data {
        try lock.withLock {
            if isUsage {
                calls += 1
                if offline { throw URLError(.notConnectedToInternet) }
                let used = calls == 1 ? 40 : 55
                return Data("{\"rate_limit\":{\"primary_window\":{\"used_percent\":\(used),\"limit_window_seconds\":18000}}}".utf8)
            }
            let expiry = offline ? 1_800_007_200 : 1_800_003_600
            return Data("{\"available_count\":1,\"expires_at\":\(expiry)}".utf8)
        }
    }
}

private final class QuotaNetworkProtocol: URLProtocol, @unchecked Sendable {
    static let state = QuotaNetworkFixture()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "chatgpt.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.state.response(isUsage: request.url!.path.hasSuffix("/usage"))
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
