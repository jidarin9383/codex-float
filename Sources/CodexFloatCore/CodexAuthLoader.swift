import Foundation

/// Local Codex login session used only to call ChatGPT quota HTTPS endpoints.
///
/// Security:
/// - Tokens live only in memory for the request lifetime.
/// - Never log, print, or persist `accessToken` / account IDs.
/// - Callers must not put tokens into `statusMessage`, diagnostics, or UserDefaults.
public struct CodexAuthSession: Sendable {
    /// Opaque bearer token. Do not log.
    public let accessToken: String
    /// Optional ChatGPT account id for request headers. Do not log.
    public let accountID: String?

    public init(accessToken: String, accountID: String? = nil) {
        self.accessToken = accessToken
        self.accountID = accountID
    }
}

public enum CodexAuthLoadError: Error, Equatable, Sendable {
    case fileMissing
    case fileTooLarge
    case malformed
    case missingAccessToken

    public var uiMessage: String {
        switch self {
        case .fileMissing:
            return "需要先登录 Codex"
        case .fileTooLarge, .malformed:
            return "Codex 登录数据无法读取"
        case .missingAccessToken:
            return "Codex 登录已失效，请重新登录"
        }
    }
}

/// Loads `auth.json` from `$CODEX_HOME` or `~/.codex` without shelling out.
public enum CodexAuthLoader {
    public static let maxAuthBytes: UInt64 = 256 * 1024

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> CodexAuthSession {
        let home = codexHome(environment: environment, fileManager: fileManager)
        let path = home.appendingPathComponent("auth.json", isDirectory: false)
        return try load(from: path, fileManager: fileManager)
    }

    public static func load(from path: URL, fileManager: FileManager = .default) throws -> CodexAuthSession {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw CodexAuthLoadError.fileMissing
        }
        let attrs = try fileManager.attributesOfItem(atPath: path.path)
        if let size = attrs[.size] as? NSNumber, size.uint64Value > maxAuthBytes {
            throw CodexAuthLoadError.fileTooLarge
        }

        let data = try Data(contentsOf: path, options: [.mappedIfSafe])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAuthLoadError.malformed
        }

        let tokens = (root["tokens"] as? [String: Any]) ?? root
        guard let accessToken = stringValue(tokens, keys: ["access_token", "accessToken"]),
              !accessToken.isEmpty
        else {
            throw CodexAuthLoadError.missingAccessToken
        }

        let accountID = stringValue(tokens, keys: ["account_id", "accountId"])
            ?? accountIDFromJWT(accessToken)

        return CodexAuthSession(accessToken: accessToken, accountID: accountID)
    }

    // MARK: - Private

    private static func codexHome(
        environment: [String: String],
        fileManager: FileManager
    ) -> URL {
        if let custom = environment["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private static func stringValue(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Best-effort parse of ChatGPT account id from JWT payload (no signature verify).
    private static func accountIDFromJWT(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - payload.count % 4) % 4
        if pad > 0 {
            payload.append(String(repeating: "=", count: pad))
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return stringValue(json, keys: [
            "https://api.openai.com/auth.chatgpt_account_id",
            "chatgpt_account_id"
        ])
    }
}
