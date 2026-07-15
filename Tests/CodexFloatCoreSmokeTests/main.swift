import Foundation
import CodexFloatCore

enum Smoke {
    static func main() async throws {
        try mathAndFixtures()
        try jsonlFraming()
        try protocolDecoding()
        try rateLimitsMapping()
        try retryBackoff()
        try staleState()
        try executableLocator()
        try await liveClientIfEnabled()

        print("CodexFloatCoreSmokeTests: all passed")
    }

    // MARK: - Existing pure helpers

    private static func mathAndFixtures() throws {
        try expect(QuotaMath.remaining(fromUsedPercent: 82) == 18, "used 82 → remaining 18")
        try expect(QuotaMath.remaining(fromUsedPercent: -5) == 100, "clamp low used")
        try expect(QuotaMath.remaining(fromUsedPercent: 150) == 0, "clamp high used")
        try expect(QuotaAttention.from(remainingPercent: 18) == .attention, "18 attention")
        try expect(QuotaAttention.from(remainingPercent: 20) == .attention, "20 attention")
        try expect(QuotaAttention.from(remainingPercent: 21) == .healthy, "21 healthy")
        try expect(QuotaAttention.from(remainingPercent: 10) == .critical, "10 critical")

        let now = Date(timeIntervalSince1970: 1_000_000)
        let target = now.addingTimeInterval(6 * 24 * 3600 + 18 * 3600)
        try expect(
            ResetTimeFormatting.relativeResetLabel(until: target, now: now) == "6 天 18 小时后重置",
            "relative multi-day label"
        )

        let absolute = ResetTimeFormatting.absoluteResetDateTimeLabel(until: target, now: now)
        try expect(absolute.contains("月"), "absolute date has month")
        try expect(absolute.contains("日"), "absolute date has day")
        try expect(absolute.contains(":"), "absolute datetime has time")

        let fixture = QuotaFixtures.current18Percent
        try expect(fixture.remainingPercent == 18, "fixture remaining")
        try expect(fixture.resetOpportunityCount == 2, "fixture reset opportunities")
    }

    // MARK: - JSONL

    private static func jsonlFraming() throws {
        var framer = JSONLFramer()
        let part1 = Data(#"{"id":1,"result":{"ok":tr"#.utf8)
        let part2 = Data((#"ue}"# + "\n" + #"{"method":"ping"}"# + "\n").utf8)
        try expect(framer.push(part1).isEmpty, "incomplete line stays buffered")
        let lines = framer.push(part2)
        try expect(lines.count == 2, "two complete lines")
        try expect(lines[0].contains("\"ok\":true"), "reassembled first line")
        try expect(lines[1] == #"{"method":"ping"}"#, "second line intact")

        var framer2 = JSONLFramer()
        _ = framer2.push(Data("partial".utf8))
        let finished = framer2.finish()
        try expect(finished == ["partial"], "finish flushes remainder")
    }

    // MARK: - Protocol decode

    private static func protocolDecoding() throws {
        let responseLine = """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1784622680},"secondary":null,"planType":"plus"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1784622680},"planType":"plus"}},"rateLimitResetCredits":{"availableCount":2}}}
        """
        let envelope = try AppServerMessageParsing.parseLine(responseLine)
        guard case .response(let id, let data) = envelope else {
            throw fail("expected response envelope")
        }
        try expect(id == .int(2), "response id")
        let decoded = try JSONDecoder().decode(WireGetAccountRateLimitsResponse.self, from: data)
        try expect(decoded.rateLimits.primary?.usedPercent == 42, "used percent")
        try expect(decoded.rateLimitResetCredits?.availableCount == 2, "reset credits")
        try expect(decoded.rateLimitsByLimitId?["codex"] != nil, "by-id map")

        // Interleaved notification should not break correlation.
        let note = #"{"method":"remoteControl/status/changed","params":{"status":"disabled"}}"#
        let noteEnv = try AppServerMessageParsing.parseLine(note)
        guard case .notification(let method, _) = noteEnv else {
            throw fail("expected notification")
        }
        try expect(method == "remoteControl/status/changed", "notification method")

        let errLine = #"{"id":3,"error":{"code":-32000,"message":"not logged in"}}"#
        let errEnv = try AppServerMessageParsing.parseLine(errLine)
        guard case .error(_, let code, let message) = errEnv else {
            throw fail("expected error envelope")
        }
        try expect(code == -32000, "error code")
        try expect(message.contains("logged"), "error message")

        // Malformed
        do {
            _ = try AppServerMessageParsing.parseLine("not-json")
            throw fail("malformed should throw")
        } catch is AppServerClientError {
            // ok
        } catch {
            // JSONSerialization error is also acceptable
        }

        // Nullable secondary / missing short window remains valid.
        let weeklyOnly = """
        {"id":9,"result":{"rateLimits":{"primary":{"usedPercent":6,"windowDurationMins":10080,"resetsAt":1},"secondary":null,"planType":"plus"},"rateLimitResetCredits":{"availableCount":2}}}
        """
        guard case .response(_, let weeklyData) = try AppServerMessageParsing.parseLine(weeklyOnly) else {
            throw fail("weekly-only response")
        }
        let weekly = try JSONDecoder().decode(WireGetAccountRateLimitsResponse.self, from: weeklyData)
        try expect(weekly.rateLimits.secondary == nil, "secondary may be null")
    }

    // MARK: - Mapping

    private static func rateLimitsMapping() throws {
        let wire = WireGetAccountRateLimitsResponse(
            rateLimits: WireRateLimitSnapshot(
                limitId: "other",
                planType: "plus",
                primary: WireRateLimitWindow(usedPercent: 90, windowDurationMins: 10080, resetsAt: 1_784_622_680)
            ),
            rateLimitsByLimitId: [
                "codex": WireRateLimitSnapshot(
                    limitId: "codex",
                    planType: "plus",
                    primary: WireRateLimitWindow(usedPercent: 82, windowDurationMins: 10080, resetsAt: 1_784_622_680),
                    secondary: nil
                ),
                "extra": WireRateLimitSnapshot(
                    limitId: "extra",
                    primary: WireRateLimitWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: nil)
                )
            ],
            rateLimitResetCredits: WireRateLimitResetCredits(availableCount: 2)
        )

        let snapshot = RateLimitsMapper.snapshot(from: wire, fetchedAt: Date(timeIntervalSince1970: 100))
        try expect(snapshot.remainingPercent == 18, "prefer codex bucket remaining")
        try expect(snapshot.planType == "Plus", "plan display")
        try expect(snapshot.resetOpportunityCount == 2, "reset opportunities mapped")
        try expect(snapshot.windows.count == 1, "do not invent secondary window")
        try expect(snapshot.windows.first?.isWeekly == true, "weekly flag from 10080 mins")

        // Missing weekly-only secondary is fine; primary without duration still accepted.
        let noDuration = WireGetAccountRateLimitsResponse(
            rateLimits: WireRateLimitSnapshot(
                primary: WireRateLimitWindow(usedPercent: 50)
            )
        )
        let mapped = RateLimitsMapper.snapshot(from: noDuration)
        try expect(mapped.remainingPercent == 50, "remaining without duration")
        try expect(mapped.windows.first?.isWeekly == true, "sole primary treated as weekly fallback")

        // Credits HTTPS enrichment (sample JSON only — never real tokens).
        let creditsJSON: [String: Any] = [
            "availableCount": 2,
            "credits": [
                ["expires_at": "2026-07-30T00:00:00Z"],
                ["expiresAt": 1_785_369_600]
            ]
        ]
        let expires = ChatGPTQuotaClient.collectExpirations(from: creditsJSON)
        try expect(expires.count == 2, "two expiry dates collected")
        let merged = RateLimitsMapper.merging(
            snapshot,
            resetCredits: ResetCreditsDetail(availableCount: 2, expiresAt: expires.sorted())
        )
        try expect(merged.resetOpportunities.count == 2, "merged rows")
        try expect(merged.resetOpportunities[0].expiresAt != nil, "first row has date")
        try expect(merged.resetOpportunities[1].expiresAt != nil, "second row has date")
    }

    // MARK: - Backoff / stale

    private static func retryBackoff() throws {
        var backoff = RetryBackoff()
        try expect(backoff.delay == 0, "no delay before failures")
        backoff.registerFailure()
        try expect(backoff.delay == 15, "first failure 15s")
        backoff.registerFailure()
        try expect(backoff.delay == 30, "second 30s")
        backoff.registerFailure()
        try expect(backoff.delay == 60, "third 60s")
        backoff.registerFailure()
        try expect(backoff.delay == 300, "fourth 5m")
        backoff.registerFailure()
        try expect(backoff.delay == 300, "capped at 5m")
        backoff.registerSuccess()
        try expect(backoff.delay == 0, "reset after success")
    }

    private static func staleState() throws {
        let fetched = Date(timeIntervalSince1970: 1_000)
        try expect(
            RateLimitsMapper.isStale(fetchedAt: fetched, now: fetched.addingTimeInterval(29 * 60)) == false,
            "under 30m not stale"
        )
        try expect(
            RateLimitsMapper.isStale(fetchedAt: fetched, now: fetched.addingTimeInterval(30 * 60)) == true,
            "30m is stale"
        )
    }

    private static func executableLocator() throws {
        // Should find something on this developer machine, but never throw.
        let found = CodexExecutableLocator.resolve()
        if let found {
            try expect(FileManager.default.isExecutableFile(atPath: found.path), "resolved path executable")
            print("executable locator: \(found.path)")
        } else {
            print("executable locator: none (ok on CI without codex)")
        }

        let missing = CodexExecutableLocator.resolve(
            override: URL(fileURLWithPath: "/tmp/codex-float-definitely-missing-\(UUID().uuidString)")
        )
        try expect(missing == nil, "missing override yields nil")
    }

    /// Opt-in live probe: CODEX_FLOAT_LIVE_PROTOCOL=1
    private static func liveClientIfEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_FLOAT_LIVE_PROTOCOL"] == "1" else {
            print("live protocol: skipped (set CODEX_FLOAT_LIVE_PROTOCOL=1 to enable)")
            return
        }
        guard let url = CodexExecutableLocator.resolve() else {
            throw fail("live protocol enabled but codex not found")
        }
        let client = CodexAppServerClient(
            configuration: .init(executableURL: url, requestTimeout: 20)
        )
        do {
            let wire = try await client.readRateLimits()
            let snapshot = RateLimitsMapper.snapshot(from: wire)
            print(
                "live protocol: remaining=\(snapshot.remainingPercent.map(String.init(describing:)) ?? "nil") plan=\(snapshot.planType ?? "nil") resets=\(String(describing: snapshot.resetsAt))"
            )
            try expect(snapshot.freshness == .current, "live snapshot current")
            try expect(snapshot.remainingPercent != nil, "live remaining present")
            if let remaining = snapshot.remainingPercent {
                try expect(remaining >= 0 && remaining <= 100, "live remaining in 0...100")
            }
            await client.shutdown()
        } catch {
            await client.shutdown()
            throw error
        }

        // Full repository path (app-server + optional ChatGPT credits merge).
        let repo = QuotaRepository()
        let full = await repo.refresh()
        print(
            "live repository: remaining=\(full.remainingPercent.map(String.init(describing:)) ?? "nil") plan=\(full.planType ?? "nil") freshness=\(full.freshness) resetCount=\(full.resetOpportunityCount.map(String.init(describing:)) ?? "nil") datedRows=\(full.resetOpportunities.filter { $0.expiresAt != nil }.count)/\(full.resetOpportunities.count) status=\(full.statusMessage ?? "nil")"
        )
        try expect(full.freshness == .current || full.freshness == .stale, "repo snapshot healthy-ish")
        if let remaining = full.remainingPercent {
            try expect(remaining >= 0 && remaining <= 100, "repo remaining range")
        }
        if let resets = full.resetsAt {
            let rel = ResetTimeFormatting.relativeResetLabel(until: resets, now: Date())
            let abs = ResetTimeFormatting.absoluteResetDateTimeLabel(until: resets, now: Date())
            print("live labels: abs=\(abs) rel=\(rel)")
            try expect(!rel.isEmpty && !abs.isEmpty, "reset labels non-empty")
        }
        await repo.shutdown()

        // Failure path: missing executable override.
        let badRepo = QuotaRepository(
            preferences: .init(executableOverride: URL(fileURLWithPath: "/tmp/codex-float-missing-\(UUID().uuidString)"))
        )
        let bad = await badRepo.refresh()
        print("failure path: freshness=\(bad.freshness) status=\(bad.statusMessage ?? "nil")")
        try expect(bad.freshness == .error, "missing codex yields error freshness")
        try expect((bad.statusMessage ?? "").contains("codex") || (bad.statusMessage ?? "").contains("未找到"), "missing codex message")
        await badRepo.shutdown()
    }

    // MARK: - Helpers

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw fail(message) }
    }

    private static func fail(_ message: String) -> NSError {
        NSError(
            domain: "CodexFloatCoreSmokeTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

do {
    try await Smoke.main()
} catch {
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    exit(1)
}
