import AppKit
import SwiftUI

/// Liquid Glass modal alerts for menu-bar utility feedback. Button label is always「好」.
@MainActor
enum UserAlerts {
    private static var activePanel: NSPanel?
    private static var hostingView: NSHostingView<GlassAlertView>?

    static func show(
        title: String,
        message: String,
        kind: GlassAlertKind = .info
    ) {
        dismiss()

        let bleed = CodexFloatTheme.panelShadowBleed
        // Height is measured after layout; start with a comfortable default.
        let contentWidth: CGFloat = 320
        let provisionalHeight: CGFloat = 148

        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: contentWidth + bleed * 2,
                height: provisionalHeight + bleed * 2
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        // Cannot combine canJoinAllSpaces + moveToActiveSpace (AppKit assertion).
        // Alerts should appear on the active Space only.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // Need key window so the「好」button receives clicks/Return.
        panel.becomesKeyOnlyIfNeeded = false

        let root = GlassAlertView(title: title, message: message, kind: kind) {
            dismiss()
        }

        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = false
        if #available(macOS 14.0, *) {
            hosting.clipsToBounds = false
        }

        // Preferred layout size from SwiftUI (fallback if fitting is zero).
        let fitting = hosting.fittingSize
        let bodyWidth = max(contentWidth, fitting.width > 1 ? fitting.width : contentWidth)
        let bodyHeight = max(provisionalHeight, fitting.height > 1 ? fitting.height : provisionalHeight)
        let panelSize = NSSize(
            width: bodyWidth + bleed * 2,
            height: bodyHeight + bleed * 2
        )
        hosting.frame = NSRect(
            x: bleed,
            y: bleed,
            width: bodyWidth,
            height: bodyHeight
        )

        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.masksToBounds = false
        if #available(macOS 14.0, *) {
            container.clipsToBounds = false
        }
        container.addSubview(hosting)
        panel.contentView = container
        panel.setContentSize(panelSize)
        center(panel, size: panelSize)

        activePanel = panel
        hostingView = hosting

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private static func center(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + 36
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    static func dismiss() {
        activePanel?.orderOut(nil)
        activePanel = nil
        hostingView = nil
    }

    static func showLaunchAtLoginEnabled() {
        show(
            title: "开机自启已开启",
            message: "下次开机，Codex Float会自动开启",
            kind: .success
        )
    }

    static func showLaunchAtLoginDisabled() {
        show(
            title: "开机自启已关闭",
            message: "下次开机，Codex Float不会自动开启",
            kind: .info
        )
    }

    static func showLaunchAtLoginFailed(_ detail: String) {
        show(
            title: "无法更改开机自启",
            message: detail,
            kind: .warning
        )
    }

    static func showAlreadyUpToDate(version: String? = nil) {
        let resolved = version ?? LaunchAtLoginService.currentVersion
        show(
            title: "已是最新版本",
            message: "Codex Float \(resolved)\n当前没有可用更新。",
            kind: .success
        )
    }

    static func showUpdateAvailable(current: String, latest: String, releaseURL: URL) {
        show(
            title: "发现新版本",
            message: "当前 \(current)，最新 \(latest)。\n将在浏览器打开 GitHub Releases。",
            kind: .info
        )
        // Open after presenting so the user still sees the notice.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    static func showUpdateNotConfigured() {
        show(
            title: "未配置更新源",
            message: "请使用 GitHub Releases 安装的正式包，或从源码仓库查看更新。",
            kind: .info
        )
    }

    static func showUpdateCheckFailed(_ detail: String) {
        show(
            title: "检查更新失败",
            message: detail,
            kind: .warning
        )
    }
}
