import AppKit
import Darwin
import SwiftUI
import CodexFloatCore

@main
struct CodexFloatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Icon-only menu bar item; click opens settings/actions menu.
        MenuBarExtra {
            MenuBarActionsView(model: appDelegate.model)
        } label: {
            MenuBarQuotaIcon(snapshot: appDelegate.model.viewModel.snapshot)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarActionsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Toggle("悬浮窗", isOn: Binding(
            get: { model.preferences.floatingWidgetVisible },
            set: { model.setFloatingWidgetVisible($0) }
        ))

        Toggle("开机自启", isOn: Binding(
            get: { model.preferences.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))

        Button("检查更新") {
            model.checkForUpdates()
        }

        Divider()

        Button("退出 \(CodexFloatTheme.productName)") {
            model.viewModel.stop()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Single shared model for menu bar + floating panel (owned here so launch always bootstraps).
    let model = AppModel()
    private var didBootstrap = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Writing to a closed codex stdio pipe must not kill the whole app (signal 13).
        signal(SIGPIPE, SIG_IGN)
        // Login agent / accidental double-launch must not open a second float + menu item.
        if SingleInstance.shouldTerminateAsDuplicate() {
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        if SingleInstance.shouldTerminateAsDuplicate() {
            NSApp.terminate(nil)
            return
        }
        // Accessory = no Dock icon; MenuBarExtra still owns the status item.
        NSApp.setActivationPolicy(.accessory)
        bootstrapIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        model.bootstrap()
    }
}
