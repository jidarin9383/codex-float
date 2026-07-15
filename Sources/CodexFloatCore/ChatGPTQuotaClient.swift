import Foundation

/// Reset-credit enrichment from ChatGPT HTTPS APIs (same endpoints as quota-float).
public struct ResetCreditsDetail: Equatable, Sendable {
    public var availableCount: Int?
    /// Sorted expiry timestamps when the API provides them.
    public var expiresAt: [Date]

    public init(availableCount: Int? = nil, expiresAt: [Date] = []) {
        self.availableCount = availableCount
        self.expiresAt = expiresAt
    }
}

public enum ChatGPTQuotaClientError: Error, Equatable, Sendable {
    case invalidURL
    case httpStatus(Int)
    case network
    case malformedBody
    case unauthorized

    public var uiMessage: String {
        switch self {
        case .unauthorized:
            return "Codex 登录已失效，请重新登录"
        case .httpStatus, .network, .malformedBody, .invalidURL:
            return "无法读取重置机会详情"
        }
    }
}

/// Fetches reset-credit details using the local Codex access token.
/// Never logs tokens, headers, or raw responses.
public actor ChatGPTQuotaClient {
    public static let usageURLString = "https://chatgpt.com/backend-api/wham/usage"
    public static let creditsURLString = "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
    public static let maxResponseBytes = 1_024 * 1_024

    private let session: URLSession
    private let usageURL: URL
    private let creditsURL: URL

    public init(session: URLSession = .shared) {
        self.session = session
        self.usageURL = URL(string: Self.usageURLString)!
        self.creditsURL = URL(string: Self.creditsURLString)!
    }

    /// Load auth from disk and fetch reset-credit enrichment.
    public func fetchResetCredits() async throws -> ResetCreditsDetail {
        let sessionAuth = try CodexAuthLoader.load()
        return try await fetchResetCredits(session: sessionAuth)
    }

    public func fetchResetCredits(session auth: CodexAuthSession) async throws -> ResetCreditsDetail {
        let headers = try makeHeaders(auth: auth)

        // Sequential on the actor so JSON `Any` stays isolated (Sendable-safe).
        let credits = try? await getJSONObject(url: creditsURL, headers: headers)
        let usage = try? await getJSONObject(url: usageURL, headers: headers)

        // Prefer dedicated credits endpoint; fall back to nested usage payload.
        var count = credits.flatMap { integerValue($0, keys: countKeys) }
        var expires = credits.map { Self.collectExpirations(from: $0) } ?? []

        if let usage {
            let nested = usage["rate_limit_reset_credits"]
                ?? usage["rateLimitResetCredits"]
            if let nested {
                if count == nil {
                    count = integerValue(nested, keys: countKeys)
                }
                if expires.isEmpty {
                    expires = Self.collectExpirations(from: nested)
                }
            }
        }

        // If both requests failed hard, surface a network error.
        if usage == nil, credits == nil {
            throw ChatGPTQuotaClientError.network
        }

        expires.sort()
        return ResetCreditsDetail(availableCount: count, expiresAt: expires)
    }

    // MARK: - HTTP

    private var countKeys: [String] {
        ["available_count", "availableCount", "remaining", "count", "quantity"]
    }

    private func makeHeaders(auth: CodexAuthSession) throws -> [String: String] {
        var headers: [String: String] = [
            "Authorization": "Bearer \(auth.accessToken)",
            "Accept": "application/json",
            "originator": "Codex Desktop",
            "OAI-Product-Sku": "CODEX"
        ]
        if let accountID = auth.accountID, !accountID.isEmpty {
            headers["ChatGPT-Account-Id"] = accountID
        }
        return headers
    }

    private func getJSONObject(url: URL, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ChatGPTQuotaClientError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw ChatGPTQuotaClientError.network
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ChatGPTQuotaClientError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ChatGPTQuotaClientError.httpStatus(http.statusCode)
        }
        guard data.count <= Self.maxResponseBytes else {
            throw ChatGPTQuotaClientError.malformedBody
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatGPTQuotaClientError.malformedBody
        }
        return object
    }

    // MARK: - JSON helpers (no secrets in outputs)

    private func integerValue(_ value: Any, keys: [String]) -> Int? {
        guard let object = value as? [String: Any] else { return nil }
        for key in keys {
            if let number = object[key] as? NSNumber {
                return number.intValue
            }
            if let text = object[key] as? String, let parsed = Int(text) {
                return parsed
            }
        }
        return nil
    }

    /// Recursively collect expiry timestamps from a credits payload.
    public static func collectExpirations(from value: Any) -> [Date] {
        var output: [Date] = []
        visit(value, into: &output)
        return output
    }

    private static func visit(_ value: Any, into output: inout [Date]) {
        if let array = value as? [Any] {
            for item in array {
                visit(item, into: &output)
            }
            return
        }
        guard let object = value as? [String: Any] else { return }

        let expiryKeys = [
            "expires_at", "expiresAt",
            "expiration_time", "expirationTime",
            "expires"
        ]
        for key in expiryKeys {
            if let date = parseDate(object[key]) {
                output.append(date)
                break
            }
        }

        for key in ["credits", "reset_credits", "resetCredits", "available", "items", "grants"] {
            if let child = object[key] {
                visit(child, into: &output)
            }
        }
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let text = value as? String {
            let full = ISO8601DateFormatter()
            full.formatOptions = [.withInternetDateTime]
            if let iso = full.date(from: text) {
                return iso
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let frac = fractional.date(from: text) {
                return frac
            }
            if let seconds = TimeInterval(text) {
                return Date(timeIntervalSince1970: seconds)
            }
            return nil
        }
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            // Heuristic: ms vs s
            if raw > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: raw / 1000)
            }
            return Date(timeIntervalSince1970: raw)
        }
        return nil
    }
}
