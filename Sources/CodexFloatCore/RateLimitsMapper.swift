import Foundation

/// Maps app-server rate-limit payloads into UI-safe `QuotaSnapshot` values.
public enum RateLimitsMapper {
    /// Weekly window duration used by Codex (7 days).
    public static let weeklyWindowMinutes: Int64 = 10_080

    /// Preferred limit bucket when multi-limit maps are present.
    public static let preferredLimitID = "codex"

    public static func snapshot(
        from response: WireGetAccountRateLimitsResponse,
        fetchedAt: Date = .now,
        freshness: QuotaFreshness = .current
    ) -> QuotaSnapshot {
        let selected = selectSnapshot(from: response)
        let windows = makeWindows(from: selected)
        let weekly = windows.first(where: \.isWeekly) ?? windows.first

        let count = response.rateLimitResetCredits.map { Int($0.availableCount) }
        return QuotaSnapshot(
            remainingPercent: weekly.map { QuotaMath.remaining(fromUsedPercent: $0.usedPercent) },
            planType: displayPlanType(selected.planType),
            resetsAt: weekly?.resetsAt,
            resetOpportunityCount: count,
            resetOpportunities: opportunities(count: count, expiresAt: []),
            windows: windows,
            fetchedAt: fetchedAt,
            freshness: freshness,
            statusMessage: nil
        )
    }

    /// Merge ChatGPT credits HTTPS detail into an app-server snapshot (dates when present).
    public static func merging(
        _ snapshot: QuotaSnapshot,
        resetCredits: ResetCreditsDetail
    ) -> QuotaSnapshot {
        var next = snapshot
        let count = resetCredits.availableCount ?? snapshot.resetOpportunityCount
        next.resetOpportunityCount = count
        next.resetOpportunities = opportunities(count: count, expiresAt: resetCredits.expiresAt)
        return next
    }

    public static func opportunities(count: Int?, expiresAt: [Date]) -> [ResetOpportunity] {
        guard let count, count > 0 else { return [] }
        return (1...count).map { index in
            let expiry = index - 1 < expiresAt.count ? expiresAt[index - 1] : nil
            return ResetOpportunity(index: index, expiresAt: expiry)
        }
    }

    public static func selectSnapshot(from response: WireGetAccountRateLimitsResponse) -> WireRateLimitSnapshot {
        if let byID = response.rateLimitsByLimitId {
            if let codex = byID[preferredLimitID] {
                return codex
            }
            // Stable fallback: first value if map is non-empty.
            if let first = byID.values.first {
                return first
            }
        }
        return response.rateLimits
    }

    public static func makeWindows(from snapshot: WireRateLimitSnapshot) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []

        if let primary = snapshot.primary {
            windows.append(
                window(
                    id: "primary",
                    from: primary,
                    fallbackWeekly: snapshot.secondary == nil
                )
            )
        }

        if let secondary = snapshot.secondary {
            windows.append(
                window(
                    id: "secondary",
                    from: secondary,
                    fallbackWeekly: false
                )
            )
        }

        return windows
    }

    public static func isWeekly(windowDurationMins: Int64?) -> Bool {
        guard let windowDurationMins else { return false }
        return windowDurationMins == weeklyWindowMinutes
    }

    public static func isStale(
        fetchedAt: Date,
        now: Date = .now,
        threshold: TimeInterval = 30 * 60
    ) -> Bool {
        now.timeIntervalSince(fetchedAt) >= threshold
    }

    // MARK: - Private

    private static func window(
        id: String,
        from wire: WireRateLimitWindow,
        fallbackWeekly: Bool
    ) -> QuotaWindow {
        let weekly = isWeekly(windowDurationMins: wire.windowDurationMins) || fallbackWeekly
        let resetsAt = wire.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let remaining = QuotaMath.remaining(fromUsedPercent: wire.usedPercent)
        return QuotaWindow(
            id: id,
            remainingPercent: remaining,
            usedPercent: wire.usedPercent,
            windowDurationMins: wire.windowDurationMins.map(Int.init),
            resetsAt: resetsAt,
            isWeekly: weekly
        )
    }

    private static func displayPlanType(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "free": return "Free"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        case "go": return "Go"
        case "prolite": return "Pro Lite"
        default:
            // Keep unknown plan labels readable without inventing meaning.
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
