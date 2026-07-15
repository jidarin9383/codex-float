import AppKit
import Foundation
import ServiceManagement

/// Enables / disables launch-at-login.
///
/// - Packaged `.app`: uses `SMAppService.mainApp` (System Settings → Login Items).
/// - Xcode / SPM bare binary: installs a user LaunchAgent for the current executable path
///   so the toggle actually does something during development.
@MainActor
enum LaunchAtLoginService {
    static let agentLabel = "app.codexfloat.mac"
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "0.1.0"

    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(agentLabel).plist")
    }

    /// Whether launch-at-login is currently active (system truth, not only UserDefaults).
    static var isEnabled: Bool {
        if isRunningInsideAppBundle {
            return SMAppService.mainApp.status == .enabled
        }
        // Dev binary: presence of the agent plist means “start at next login”.
        // Do not require the job to be loaded now — loading it would spawn a second instance.
        return FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    static var statusDescription: String {
        if isRunningInsideAppBundle {
            switch SMAppService.mainApp.status {
            case .enabled:
                return "已开启（系统登录项）"
            case .requiresApproval:
                return "待批准：请到 系统设置 → 通用 → 登录项与扩展 中允许 Codex Float"
            case .notRegistered:
                return "未开启"
            case .notFound:
                return "未找到应用包（请安装 .app 后再试）"
            @unknown default:
                return "状态未知"
            }
        }
        if isEnabled {
            return "已开启（下次登录时自动启动）"
        }
        return "未开启"
    }

    /// Apply the desired state. Throws with a localized Chinese message on failure.
    static func setEnabled(_ enabled: Bool) throws {
        if isRunningInsideAppBundle {
            try setMainAppServiceEnabled(enabled)
        } else {
            try setLaunchAgentEnabled(enabled)
        }
    }

    // MARK: - SMAppService (.app)

    private static var isRunningInsideAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private static func setMainAppServiceEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status == .enabled { return }
            do {
                try service.register()
            } catch {
                throw LaunchAtLoginError.registrationFailed(error.localizedDescription)
            }
            if service.status == .requiresApproval {
                throw LaunchAtLoginError.requiresApproval
            }
        } else {
            if service.status == .notRegistered { return }
            do {
                try service.unregister()
            } catch {
                throw LaunchAtLoginError.registrationFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - LaunchAgent (dev / unpackaged)

    private static func setLaunchAgentEnabled(_ enabled: Bool) throws {
        if enabled {
            let executable = try resolvedExecutablePath()
            // Only install the LaunchAgent for *next* login.
            // Do not `launchctl bootstrap` now — that would start a second instance immediately.
            try writeAgentPlist(executablePath: executable)
        } else {
            try bootoutAgent()
            try? FileManager.default.removeItem(at: agentPlistURL)
        }
    }

    private static func resolvedExecutablePath() throws -> String {
        if let url = Bundle.main.executableURL {
            return url.path
        }
        if let first = CommandLine.arguments.first {
            let url = URL(fileURLWithPath: first).standardizedFileURL
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url.path
            }
        }
        throw LaunchAtLoginError.executableNotFound
    }

    private static func writeAgentPlist(executablePath: String) throws {
        let dir = agentPlistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: agentPlistURL, options: .atomic)
    }

    private static func bootoutAgent() throws {
        let uid = getuid()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(uid)/\(agentLabel)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        // Non-zero is fine if the job was not loaded.
    }
}

enum LaunchAtLoginError: LocalizedError {
    case requiresApproval
    case executableNotFound
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "已请求开机自启，请到「系统设置 → 通用 → 登录项与扩展」中允许 Codex Float。"
        case .executableNotFound:
            return "找不到可执行文件路径，无法注册开机自启。"
        case .registrationFailed(let detail):
            return "无法设置开机自启：\(detail)"
        }
    }
}
