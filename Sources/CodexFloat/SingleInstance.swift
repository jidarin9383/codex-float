import AppKit
import Foundation

/// Ensures only one Codex Float process stays alive (login agent / double-launch safe).
@MainActor
enum SingleInstance {
    /// Returns `true` if another copy is already running and this process should exit.
    static func shouldTerminateAsDuplicate() -> Bool {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myPath = Bundle.main.executableURL?.resolvingSymlinksInPath().path
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path

        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != myPID else { continue }

            if app.bundleIdentifier == "app.codexfloat.mac" {
                return true
            }

            if let other = app.executableURL?.resolvingSymlinksInPath().path,
               !myPath.isEmpty,
               other == myPath
            {
                return true
            }

            // Xcode / SPM product name fallback.
            if app.executableURL?.lastPathComponent == "CodexFloat",
               app.activationPolicy == .accessory || app.activationPolicy == .prohibited || app.activationPolicy == .regular
            {
                // Avoid matching unrelated tools; require same parent directory when possible.
                if let otherDir = app.executableURL?.deletingLastPathComponent().path,
                   let myDir = Bundle.main.executableURL?.deletingLastPathComponent().path,
                   otherDir == myDir
                {
                    return true
                }
            }
        }
        return false
    }
}
