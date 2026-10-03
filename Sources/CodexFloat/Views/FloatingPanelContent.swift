import SwiftUI
import CodexFloatCore

/// Root content hosted inside the floating NSPanel.
/// Adds shadow bleed padding so rounded elevation is not clipped to a rectangle.
struct FloatingPanelContent: View {
    @Bindable var viewModel: QuotaViewModel
    var onClose: () -> Void
    var onLayoutChange: () -> Void

    var body: some View {
        Group {
            if viewModel.isExpanded {
                DetailPanelView(
                    snapshot: viewModel.snapshot,
                    isResetListExpanded: viewModel.isResetOpportunityListExpanded,
                    canExpandResetList: viewModel.canExpandResetOpportunityList,
                    onCollapse: {
                        viewModel.collapse()
                        onLayoutChange()
                    },
                    onToggleResetList: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            viewModel.setResetOpportunityListExpanded(
                                !viewModel.isResetOpportunityListExpanded
                            )
                        }
                        onLayoutChange()
                    }
                )
            } else {
                CompactWidgetView(snapshot: viewModel.snapshot)
                    .contentShape(Capsule(style: .continuous))
                    .onTapGesture {
                        viewModel.expand()
                        onLayoutChange()
                    }
            }
        }
        .padding(CodexFloatTheme.panelShadowBleed)
        .animation(.easeOut(duration: 0.2), value: viewModel.isExpanded)
        .animation(.easeOut(duration: 0.18), value: viewModel.isResetOpportunityListExpanded)
        .onChange(of: viewModel.snapshot.usesFiveHourGlance) { _, _ in
            onLayoutChange()
        }
        .contextMenu {
            Button(viewModel.isManuallyRefreshing ? "正在刷新…" : "立即刷新") {
                Task { await viewModel.refreshManually() }
            }
            .disabled(viewModel.isManuallyRefreshing || viewModel.useStaticFixtures)
            Divider()
            Button("关闭悬浮窗", action: onClose)
        }
    }
}
