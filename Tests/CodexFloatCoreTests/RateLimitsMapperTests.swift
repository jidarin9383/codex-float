import XCTest
@testable import CodexFloatCore

final class RateLimitsMapperTests: XCTestCase {
    func testExactWeeklyWindowPopulatesTopLevelQuota() {
        let snapshot = RateLimitsMapper.snapshot(
            from: response(primary: window(used: 82, duration: 10_080))
        )

        XCTAssertEqual(snapshot.remainingPercent, 18)
        XCTAssertEqual(snapshot.windows.first?.isWeekly, true)
    }

    func testSoleShortWindowDoesNotBecomeWeekly() {
        let snapshot = RateLimitsMapper.snapshot(
            from: response(primary: window(used: 73, duration: 300))
        )

        XCTAssertNil(snapshot.remainingPercent)
        XCTAssertNil(snapshot.resetsAt)
        XCTAssertEqual(snapshot.windows.first?.isWeekly, false)
    }

    func testUnknownDurationDoesNotBecomeWeekly() {
        let snapshot = RateLimitsMapper.snapshot(
            from: response(primary: window(used: 50, duration: nil))
        )

        XCTAssertNil(snapshot.remainingPercent)
        XCTAssertEqual(snapshot.windows.first?.isWeekly, false)
    }

    func testTwoNonWeeklyWindowsDoNotPopulateTopLevelQuota() {
        let snapshot = RateLimitsMapper.snapshot(
            from: response(
                primary: window(used: 10, duration: 60),
                secondary: window(used: 20, duration: 300)
            )
        )

        XCTAssertNil(snapshot.remainingPercent)
        XCTAssertEqual(snapshot.windows.filter(\.isWeekly).count, 0)
    }

    func testHTTPSDetailAddsDatesWithoutReplacingAppServerCount() {
        let appServer = RateLimitsMapper.snapshot(
            from: response(
                primary: window(used: 82, duration: 10_080),
                resetCount: 1
            )
        )
        let firstExpiry = Date(timeIntervalSince1970: 1_800_000_000)
        let secondExpiry = firstExpiry.addingTimeInterval(86_400)

        let merged = RateLimitsMapper.merging(
            appServer,
            resetCredits: ResetCreditsDetail(
                availableCount: 9,
                expiresAt: [firstExpiry, secondExpiry]
            )
        )

        XCTAssertEqual(merged.resetOpportunityCount, 1)
        XCTAssertEqual(merged.resetOpportunities.count, 1)
        XCTAssertEqual(merged.resetOpportunities.first?.expiresAt, firstExpiry)
    }

    func testResetOpportunityCountIsBoundedBeforeAllocation() {
        XCTAssertEqual(RateLimitsMapper.opportunities(count: 100, expiresAt: []).count, 100)
        XCTAssertTrue(RateLimitsMapper.opportunities(count: 101, expiresAt: []).isEmpty)
        XCTAssertTrue(RateLimitsMapper.opportunities(count: Int.max, expiresAt: []).isEmpty)

        let snapshot = RateLimitsMapper.snapshot(
            from: response(
                primary: window(used: 82, duration: 10_080),
                resetCount: 101
            )
        )
        XCTAssertNil(snapshot.resetOpportunityCount)
        XCTAssertTrue(snapshot.resetOpportunities.isEmpty)
    }

    func testMenuBarAccessibilityAlwaysAnnouncesFreshnessWithQuota() {
        var snapshot = QuotaSnapshot(remainingPercent: 18, freshness: .current)
        XCTAssertEqual(
            QuotaAccessibility.menuBarLabel(productName: "Codex Float", snapshot: snapshot),
            "Codex Float 剩余 18%，数据最新"
        )

        snapshot.freshness = .stale
        XCTAssertEqual(
            QuotaAccessibility.menuBarLabel(productName: "Codex Float", snapshot: snapshot),
            "Codex Float 剩余 18%，数据可能不是最新"
        )

        snapshot.freshness = .error
        snapshot.statusMessage = "无法读取额度"
        XCTAssertEqual(
            QuotaAccessibility.menuBarLabel(productName: "Codex Float", snapshot: snapshot),
            "Codex Float 剩余 18%，无法读取额度"
        )
    }

    private func response(
        primary: WireRateLimitWindow?,
        secondary: WireRateLimitWindow? = nil,
        resetCount: Int64? = nil
    ) -> WireGetAccountRateLimitsResponse {
        WireGetAccountRateLimitsResponse(
            rateLimits: WireRateLimitSnapshot(primary: primary, secondary: secondary),
            rateLimitResetCredits: resetCount.map(WireRateLimitResetCredits.init(availableCount:))
        )
    }

    private func window(used: Double, duration: Int64?) -> WireRateLimitWindow {
        WireRateLimitWindow(
            usedPercent: used,
            windowDurationMins: duration,
            resetsAt: 1_800_000_000
        )
    }
}
