import Foundation

/// Checks GitHub Releases for a newer marketing version (public repos only, no token).
enum UpdateChecker {
    enum Outcome: Sendable, Equatable {
        case upToDate(current: String)
        case updateAvailable(current: String, latest: String, releaseURL: URL)
        case notConfigured
        case failure(String)
    }

    struct ReleaseInfo: Sendable, Equatable {
        var tagName: String
        var htmlURL: URL?
    }

    /// `owner/repo` from packaged Info.plist (`CodexFloatGitHubRepo`) or environment.
    static var configuredRepository: String? {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "CodexFloatGitHubRepo") as? String {
            let trimmed = fromPlist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let fromEnv = ProcessInfo.processInfo.environment["CODEX_FLOAT_GITHUB_REPO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fromEnv.isEmpty
        {
            return fromEnv
        }
        return nil
    }

    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "0.1.0"
    }

    static func checkLatest(
        session: URLSession = .shared,
        repository: String? = nil,
        currentVersion: String? = nil
    ) async -> Outcome {
        guard let repo = repository ?? configuredRepository else {
            return .notConfigured
        }
        let parts = repo.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return .failure("更新源配置无效（需要 owner/repo）")
        }

        let current = currentVersion ?? self.currentVersion
        guard let url = URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/releases/latest") else {
            return .failure("无法构造更新检查地址")
        }

        var request = URLRequest(url: url)
        request.setValue("CodexFloat/\(current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200:
                    break
                case 404:
                    return .failure("尚未发布 GitHub Release，或仓库地址不正确")
                case 403:
                    return .failure("GitHub API 暂时不可用（可能触发频率限制）")
                default:
                    return .failure("检查更新失败（HTTP \(http.statusCode)）")
                }
            }

            guard let release = parseLatestRelease(data: data) else {
                return .failure("无法解析 GitHub Release 信息")
            }

            let latest = normalizeVersion(release.tagName)
            let currentNorm = normalizeVersion(current)
            if compareSemver(latest, currentNorm) == .orderedDescending {
                let page = release.htmlURL
                    ?? URL(string: "https://github.com/\(parts[0])/\(parts[1])/releases/latest")!
                return .updateAvailable(current: currentNorm, latest: latest, releaseURL: page)
            }
            return .upToDate(current: currentNorm)
        } catch {
            return .failure("网络错误：\(error.localizedDescription)")
        }
    }

    // MARK: - Parsing / versions

    static func parseLatestRelease(data: Data) -> ReleaseInfo? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = json["tag_name"] as? String
        else {
            return nil
        }
        let html = (json["html_url"] as? String).flatMap(URL.init(string:))
        return ReleaseInfo(tagName: tag, htmlURL: html)
    }

    /// Strip a leading `v` / `V` and whitespace.
    static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.first == "v" || s.first == "V" {
            s = String(s.dropFirst())
        }
        return s
    }

    /// Compare `major.minor.patch` (extra segments ignored; missing treated as 0).
    static func compareSemver(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = versionParts(lhs)
        let r = versionParts(rhs)
        let count = max(l.count, r.count)
        for i in 0..<count {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b {
                return a < b ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    private static func versionParts(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            let digits = part.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }
}
