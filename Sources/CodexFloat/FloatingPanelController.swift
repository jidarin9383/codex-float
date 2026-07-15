import AppKit
import SwiftUI

/// Owns a non-activating, borderless floating NSPanel for the widget / detail.
@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingPanelContent>?
    private let viewModel: QuotaViewModel

    init(viewModel: QuotaViewModel) {
        self.viewModel = viewModel
    }

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else {
            panel?.orderOut(nil)
        }
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        resizeToCurrentState(animated: false)
        panel?.orderFrontRegardless()
    }

    func refreshContent() {
        guard panel != nil else { return }
        hostingView?.rootView = makeRootView()
        resizeToCurrentState(animated: true)
    }

    private func makeRootView() -> FloatingPanelContent {
        FloatingPanelContent(
            viewModel: viewModel,
            onLayoutChange: { [weak self] in
                self?.resizeToCurrentState(animated: true)
            }
        )
    }

    private func createPanel() {
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        let initial = CodexFloatTheme.panelSize(expanded: false)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // AppKit window shadow is rectangular — use SwiftUI shape-following shadow instead.
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.becomesKeyOnlyIfNeeded = true

        let hosting = NSHostingView(rootView: makeRootView())
        hosting.frame = NSRect(origin: .zero, size: initial)
        // Critical: do not clip rounded shadow bleed to the panel's rectangular bounds.
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = false
        if #available(macOS 14.0, *) {
            hosting.clipsToBounds = false
        }

        let container = NSView(frame: NSRect(origin: .zero, size: initial))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.masksToBounds = false
        if #available(macOS 14.0, *) {
            container.clipsToBounds = false
        }
        container.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        panel.contentView = container
        // Transparent panels must not clip their content views' soft edges.
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.masksToBounds = false

        self.panel = panel
        self.hostingView = hosting

        positionDefault(panel)
    }

    private func resizeToCurrentState(animated: Bool) {
        guard let panel else { return }
        let size = CodexFloatTheme.panelSize(
            expanded: viewModel.isExpanded,
            resetRowsVisible: viewModel.visibleResetOpportunityDetailRows
        )
        let current = panel.frame
        // Keep the visual trailing edge of the *content* stable (account for shadow bleed).
        let bleed = CodexFloatTheme.panelShadowBleed
        let contentTrailing = current.maxX - bleed
        let contentTop = current.maxY - bleed
        let newOrigin = NSPoint(
            x: contentTrailing - size.width + bleed,
            y: contentTop - size.height + bleed
        )
        let frame = NSRect(origin: newOrigin, size: size)
        hostingView?.rootView = makeRootView()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        hostingView?.frame = NSRect(origin: .zero, size: size)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
    }

    private func positionDefault(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = CodexFloatTheme.panelSize(expanded: false, resetRowsVisible: 0)
        let bleed = CodexFloatTheme.panelShadowBleed
        // Place so the glass content (inside bleed) sits near the right edge.
        let origin = NSPoint(
            x: visible.maxX - size.width + bleed - 12,
            y: visible.midY - size.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
