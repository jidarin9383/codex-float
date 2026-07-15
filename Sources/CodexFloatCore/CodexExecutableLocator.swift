import Foundation

/// Resolves the local `codex` executable without invoking a shell.
public enum CodexExecutableLocator: Sendable {
    /// Ordered discovery:
    /// 1. explicit override
    /// 2. directories from `PATH`
    /// 3. known Homebrew / npm layout hints
    public static func resolve(
        override: URL? = nil,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        fileManager: FileManager = .default
    ) -> URL? {
        if let override {
            return isExecutable(override, fileManager: fileManager) ? override : nil
        }

        var candidates: [URL] = []

        if let pathEnvironment {
            for directory in pathEnvironment.split(separator: ":") {
                let base = URL(fileURLWithPath: String(directory), isDirectory: true)
                candidates.append(base.appendingPathComponent("codex"))
            }
        }

        // Known layouts (verified when present; never download).
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".local/bin/codex")
        ])

        var seen = Set<String>()
        for candidate in candidates {
            let path = candidate.path
            guard seen.insert(path).inserted else { continue }
            if isExecutable(candidate, fileManager: fileManager) {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    private static func isExecutable(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: url.path)
    }
}
