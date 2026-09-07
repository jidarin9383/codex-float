import XCTest
@testable import CodexFloatCore

final class ChatGPTQuotaClientTests: XCTestCase {
    func testUsageJSONExposesFiveHourWindowAndIgnoresWeekly() {
        let usage: [String: Any] = [
            "plan_type": "plus",
            "rate_limit": [
                "primary_window": [
                    "used_percent": 40,
                    "limit_window_seconds": 18_000,
                    "reset_at": 1_800_010_800
                ],
                "secondary_window": [
                    "used_percent": 82,
                    "limit_window_seconds": 604_800,
                    "reset_at": 1_800_086_400
                ]
            ]
        ]

        let window = ChatGPTQuotaClient.fiveHourWindow(from: usage)
        XCTAssertEqual(window?.windowDurationMins, 300)
        XCTAssertEqual(window?.remainingPercent, 60)
        XCTAssertEqual(window?.isFiveHour, true)
        XCTAssertEqual(window?.resetsAt, Date(timeIntervalSince1970: 1_800_010_800))
    }

    func testWeeklyOnlyUsageDoesNotInventFiveHourWindow() {
        let usage: [String: Any] = [
            "rate_limit": [
                "primary_window": [
                    "used_percent": 12,
                    "limit_window_seconds": 604_800,
                    "reset_at": 1_800_086_400
                ]
            ]
        ]

        XCTAssertNil(ChatGPTQuotaClient.fiveHourWindow(from: usage))
    }
}
