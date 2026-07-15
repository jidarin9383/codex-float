import Foundation

// MARK: - Wire types (defensive decoding)

/// Integer-or-string request id used by the app-server.
public enum AppServerRequestID: Hashable, Sendable, Codable {
    case int(Int64)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.typeMismatch(
            AppServerRequestID.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Request id must be int or string")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

public struct AppServerClientInfo: Encodable, Sendable {
    public var name: String
    public var version: String
    public var title: String?

    public init(name: String, version: String, title: String? = nil) {
        self.name = name
        self.version = version
        self.title = title
    }
}

public struct AppServerInitializeParams: Encodable, Sendable {
    public var clientInfo: AppServerClientInfo
    public var capabilities: [String: Bool]

    public init(
        clientInfo: AppServerClientInfo = .init(name: "CodexFloat", version: "0.1.0"),
        capabilities: [String: Bool] = [:]
    ) {
        self.clientInfo = clientInfo
        self.capabilities = capabilities
    }
}

/// One rate-limit window from the protocol.
public struct WireRateLimitWindow: Decodable, Equatable, Sendable {
    public var usedPercent: Double
    public var windowDurationMins: Int64?
    public var resetsAt: Int64?

    public init(usedPercent: Double, windowDurationMins: Int64? = nil, resetsAt: Int64? = nil) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Accept int or double for usedPercent.
        if let intValue = try? container.decode(Int.self, forKey: .usedPercent) {
            usedPercent = Double(intValue)
        } else {
            usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        }
        windowDurationMins = try container.decodeIfPresent(Int64.self, forKey: .windowDurationMins)
        resetsAt = try container.decodeIfPresent(Int64.self, forKey: .resetsAt)
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent, windowDurationMins, resetsAt
    }
}

public struct WireRateLimitSnapshot: Decodable, Equatable, Sendable {
    public var limitId: String?
    public var limitName: String?
    public var planType: String?
    public var primary: WireRateLimitWindow?
    public var secondary: WireRateLimitWindow?
    public var rateLimitReachedType: String?

    public init(
        limitId: String? = nil,
        limitName: String? = nil,
        planType: String? = nil,
        primary: WireRateLimitWindow? = nil,
        secondary: WireRateLimitWindow? = nil,
        rateLimitReachedType: String? = nil
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.rateLimitReachedType = rateLimitReachedType
    }
}

public struct WireRateLimitResetCredits: Decodable, Equatable, Sendable {
    public var availableCount: Int64

    public init(availableCount: Int64) {
        self.availableCount = availableCount
    }
}

public struct WireGetAccountRateLimitsResponse: Decodable, Equatable, Sendable {
    public var rateLimits: WireRateLimitSnapshot
    public var rateLimitsByLimitId: [String: WireRateLimitSnapshot]?
    public var rateLimitResetCredits: WireRateLimitResetCredits?

    public init(
        rateLimits: WireRateLimitSnapshot,
        rateLimitsByLimitId: [String: WireRateLimitSnapshot]? = nil,
        rateLimitResetCredits: WireRateLimitResetCredits? = nil
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
        self.rateLimitResetCredits = rateLimitResetCredits
    }
}

// MARK: - Envelope parsing

public enum AppServerEnvelope: Equatable, Sendable {
    case response(id: AppServerRequestID, result: Data)
    case error(id: AppServerRequestID, code: Int64, message: String)
    case notification(method: String, params: Data?)
    case unknown
}

public enum AppServerMessageParsing {
    public static func parseLine(_ line: String) throws -> AppServerEnvelope {
        let data = Data(line.utf8)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppServerClientError.malformedMessage("root is not an object")
        }

        if let errorObj = root["error"] as? [String: Any], root["id"] != nil {
            let id = try decodeRequestID(root["id"])
            let code = (errorObj["code"] as? NSNumber)?.int64Value
                ?? Int64(errorObj["code"] as? Int ?? 0)
            let message = errorObj["message"] as? String ?? "unknown error"
            return .error(id: id, code: code, message: message)
        }

        if root["result"] != nil, root["id"] != nil {
            let id = try decodeRequestID(root["id"])
            let resultData = try extractKeyedJSON(from: root, key: "result")
            return .response(id: id, result: resultData)
        }

        if let method = root["method"] as? String, root["id"] == nil {
            let paramsData = try? extractKeyedJSON(from: root, key: "params")
            return .notification(method: method, params: paramsData)
        }

        return .unknown
    }

    private static func decodeRequestID(_ value: Any?) throws -> AppServerRequestID {
        if let number = value as? NSNumber {
            return .int(number.int64Value)
        }
        if let int = value as? Int {
            return .int(Int64(int))
        }
        if let int64 = value as? Int64 {
            return .int(int64)
        }
        if let string = value as? String {
            return .string(string)
        }
        throw AppServerClientError.malformedMessage("invalid request id")
    }

    private static func extractKeyedJSON(from root: [String: Any], key: String) throws -> Data {
        guard let value = root[key], !(value is NSNull) else {
            throw AppServerClientError.malformedMessage("missing key \(key)")
        }
        return try JSONSerialization.data(withJSONObject: value)
    }
}

// MARK: - Errors

public enum AppServerClientError: Error, Equatable, Sendable {
    case executableNotFound
    case processExited(status: Int32)
    case timeout
    case notRunning
    case malformedMessage(String)
    case protocolError(code: Int64, message: String)
    case unexpectedResponse
    case ioFailure(String)

    public var uiMessage: String {
        switch self {
        case .executableNotFound:
            return "未找到 codex 可执行文件"
        case .processExited:
            return "codex app-server 已退出"
        case .timeout:
            return "读取额度超时"
        case .notRunning:
            return "尚未连接 codex"
        case .malformedMessage:
            return "额度数据格式异常"
        case .protocolError(_, let message):
            if message.localizedCaseInsensitiveContains("login")
                || message.localizedCaseInsensitiveContains("auth")
                || message.localizedCaseInsensitiveContains("unauthor")
            {
                return "需要先登录 Codex CLI"
            }
            return "读取额度失败"
        case .unexpectedResponse:
            return "额度响应无法识别"
        case .ioFailure:
            return "无法与 codex 通信"
        }
    }
}
