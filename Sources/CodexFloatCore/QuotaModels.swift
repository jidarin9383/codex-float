import Foundation

/// Semantic freshness of a quota snapshot shown in the UI.
public enum QuotaFreshness: Equatable, Sendable {
    case loading
    case current
    case stale
    case error
}

/// Battery-like attention level for remaining quota color.
public enum QuotaAttention: Equatable, Sendable {
    case healthy
    case attention
    case critical
    case unknown

    public static func from(remainingPercent: Double?) -> QuotaAttention {
        guard let remainingPercent else { return .unknown }
        switch remainingPercent {
        case let value where value > 20:
            return .healthy
        case let value where value > 10:
            return .attention
        default:
            return .critical
        }
    }
}

/// One limit window returned by Codex (weekly, short, or unlabeled).
public struct QuotaWindow: Equatable, Sendable, Identifiable {
    public var id: String
    public var remainingPercent: Double
    public var usedPercent: Double
    public var windowDurationMins: Int?
    public var resetsAt: Date?
    public var isWeekly: Bool

    public init(
        id: String,
        remainingPercent: Double,
        usedPercent: Double,
        windowDurationMins: Int? = nil,
        resetsAt: Date? = nil,
        isWeekly: Bool = false
    ) {
        self.id = id
        self.remainingPercent = remainingPercent
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
        self.isWeekly = isWeekly
    }
}

/// One rate-limit reset credit shown in the detail panel.
public struct ResetOpportunity: Equatable, Sendable, Identifiable {
    public var id: Int
    /// 1-based index for display (`第 1 次`).
    public var index: Int
    public var expiresAt: Date?

    public init(index: Int, expiresAt: Date? = nil) {
        self.id = index
        self.index = index
        self.expiresAt = expiresAt
    }
}

/// UI-safe quota snapshot. Never contains credentials.
public struct QuotaSnapshot: Equatable, Sendable {
    public var remainingPercent: Double?
    public var planType: String?
    public var resetsAt: Date?
    public var resetOpportunityCount: Int?
    /// Per-credit rows (optional expiry when ChatGPT credits API provides it).
    public var resetOpportunities: [ResetOpportunity]
    public var windows: [QuotaWindow]
    public var fetchedAt: Date
    public var freshness: QuotaFreshness
    public var statusMessage: String?

    public var attention: QuotaAttention {
        switch freshness {
        case .loading, .error:
            return .unknown
        case .stale, .current:
            return .from(remainingPercent: remainingPercent)
        }
    }

    public init(
        remainingPercent: Double? = nil,
        planType: String? = nil,
        resetsAt: Date? = nil,
        resetOpportunityCount: Int? = nil,
        resetOpportunities: [ResetOpportunity] = [],
        windows: [QuotaWindow] = [],
        fetchedAt: Date = .now,
        freshness: QuotaFreshness = .loading,
        statusMessage: String? = nil
    ) {
        self.remainingPercent = remainingPercent
        self.planType = planType
        self.resetsAt = resetsAt
        self.resetOpportunityCount = resetOpportunityCount
        self.resetOpportunities = resetOpportunities
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.freshness = freshness
        self.statusMessage = statusMessage
    }
}

/// Pure helpers shared by UI and future repository code.
public enum QuotaMath {
    /// Convert Codex used percent into remaining percent, clamped to 0...100.
    public static func remaining(fromUsedPercent used: Double) -> Double {
        min(100, max(0, 100 - used))
    }

    public static func formatPercent(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))%"
        }
        return String(format: "%.0f%%", value)
    }
}

/// Accessibility copy for compact surfaces that cannot show freshness as text.
public enum QuotaAccessibility {
    public static func menuBarLabel(productName: String, snapshot: QuotaSnapshot) -> String {
        guard let remaining = snapshot.remainingPercent, snapshot.freshness != .loading else {
            return snapshot.statusMessage ?? productName
        }

        let value = "\(productName) 剩余 \(QuotaMath.formatPercent(remaining))"
        switch snapshot.freshness {
        case .current:
            return "\(value)，数据最新"
        case .stale:
            return "\(value)，数据可能不是最新"
        case .error:
            return "\(value)，\(snapshot.statusMessage ?? "读取失败")"
        case .loading:
            return snapshot.statusMessage ?? productName
        }
    }
}

public enum ResetTimeFormatting {
    /// Relative Chinese label such as `6 天 18 小时后重置`.
    public static func relativeResetLabel(until date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "即将重置" }

        let totalHours = Int(seconds / 3600)
        let days = totalHours / 24
        let hours = totalHours % 24

        if days > 0 && hours > 0 {
            return "\(days) 天 \(hours) 小时后重置"
        }
        if days > 0 {
            return "\(days) 天后重置"
        }
        if hours > 0 {
            return "\(hours) 小时后重置"
        }

        let minutes = max(1, Int(seconds / 60))
        return "\(minutes) 分钟后重置"
    }

    /// Absolute calendar date such as `7 月 20 日` or `2026 年 7 月 20 日`.
    public static func absoluteResetDateLabel(
        until date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "zh_CN")
    ) -> String {
        let nowComponents = calendar.dateComponents([.year], from: now)
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let formatter = DateFormatter()
        formatter.locale = locale
        if dateComponents.year == nowComponents.year {
            formatter.dateFormat = "M 月 d 日"
        } else {
            formatter.dateFormat = "yyyy 年 M 月 d 日"
        }
        return formatter.string(from: date)
    }

    /// Absolute local time such as `14:30`.
    public static func absoluteResetTimeLabel(
        until date: Date,
        locale: Locale = Locale(identifier: "zh_CN")
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Combined primary line for detail UI: `7 月 20 日 14:30`.
    public static func absoluteResetDateTimeLabel(
        until date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "zh_CN")
    ) -> String {
        let day = absoluteResetDateLabel(until: date, now: now, calendar: calendar, locale: locale)
        let time = absoluteResetTimeLabel(until: date, locale: locale)
        return "\(day) \(time)"
    }
}

/// Fixed design fixtures for static UI work (Tech-Spec step 1).
public enum QuotaFixtures {
    public static let designNow = Date(timeIntervalSince1970: 1_784_000_000)

    /// DESIGN.md fixture: 18% remaining (orange band), Plus plan, 2 reset opportunities.
    public static var current18Percent: QuotaSnapshot {
        let resetsAt = designNow.addingTimeInterval(6 * 24 * 3600 + 18 * 3600)
        let credit1 = designNow.addingTimeInterval(9 * 24 * 3600)
        let credit2 = designNow.addingTimeInterval(16 * 24 * 3600)
        return QuotaSnapshot(
            remainingPercent: 18,
            planType: "Plus",
            resetsAt: resetsAt,
            resetOpportunityCount: 2,
            resetOpportunities: [
                ResetOpportunity(index: 1, expiresAt: credit1),
                ResetOpportunity(index: 2, expiresAt: credit2)
            ],
            windows: [
                QuotaWindow(
                    id: "weekly",
                    remainingPercent: 18,
                    usedPercent: 82,
                    windowDurationMins: 10_080,
                    resetsAt: resetsAt,
                    isWeekly: true
                )
            ],
            fetchedAt: designNow,
            freshness: .current
        )
    }

    public static var loading: QuotaSnapshot {
        QuotaSnapshot(freshness: .loading, statusMessage: "正在读取额度…")
    }

    public static var stale18Percent: QuotaSnapshot {
        var snapshot = current18Percent
        snapshot.freshness = .stale
        snapshot.statusMessage = "数据可能不是最新"
        snapshot.fetchedAt = designNow.addingTimeInterval(-40 * 60)
        return snapshot
    }

    public static var limitReached: QuotaSnapshot {
        var snapshot = current18Percent
        snapshot.remainingPercent = 0
        snapshot.windows = [
            QuotaWindow(
                id: "weekly",
                remainingPercent: 0,
                usedPercent: 100,
                windowDurationMins: 10_080,
                resetsAt: snapshot.resetsAt,
                isWeekly: true
            )
        ]
        return snapshot
    }

    public static var loggedOut: QuotaSnapshot {
        QuotaSnapshot(
            freshness: .error,
            statusMessage: "需要先登录 Codex CLI"
        )
    }

    public static var codexMissing: QuotaSnapshot {
        QuotaSnapshot(
            freshness: .error,
            statusMessage: "未找到 codex 可执行文件"
        )
    }
}
