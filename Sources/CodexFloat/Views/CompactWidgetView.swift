import SwiftUI
import CodexFloatCore

/// Collapsed edge widget: one liquid-glass capsule with capacity fill flush to the edge.
/// No nested pill, no gray empty track, no inset stroke gap around the fill.
struct CompactWidgetView: View {
    let snapshot: QuotaSnapshot

    var body: some View {
        ZStack(alignment: .leading) {
            // Layer 1 — glass body (same silhouette as clip).
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)

            // Layer 2 — soft top sheen only (no inset border ring).
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            // Layer 3 — capacity fill: full height, flush left/top/bottom; width = remaining %.
            GeometryReader { geo in
                let filled = max(0, min(geo.size.width, geo.size.width * fillFraction))
                if filled > 0 {
                    Rectangle()
                        .fill(capacityGradient)
                        .frame(width: filled, height: geo.size.height)
                        .opacity(0.90)
                }
            }
            .allowsHitTesting(false)

            // Layer 4 — content over the fill/glass.
            HStack(spacing: 8) {
                CodexFloatLogoMarkV2(style: contentOnFill ? .whiteOnDark : .darkOnLight)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)

                percentageText

                if showsRemainingLabel {
                    Text("剩余")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(contentOnFill ? Color.white.opacity(0.85) : Color.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
        }
        .frame(width: CodexFloatTheme.widgetSize.width, height: CodexFloatTheme.widgetSize.height)
        // Clip → compositingGroup → shadow so elevation follows the capsule alpha, not a rect.
        .liquidGlassChrome(shape: Capsule(style: .continuous), edgeWidth: 0.95, emphasized: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var percentageText: some View {
        Group {
            if let remaining = snapshot.remainingPercent, snapshot.freshness != .loading {
                Text(QuotaMath.formatPercent(remaining))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(contentOnFill ? Color.white : Color.primary)
            } else {
                Text("—")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(contentOnFill ? Color.white.opacity(0.9) : Color.secondary)
            }
        }
    }

    private var fillFraction: CGFloat {
        guard let remaining = snapshot.remainingPercent, snapshot.freshness != .loading else {
            return 0
        }
        return CGFloat(min(100, max(0, remaining)) / 100)
    }

    private var capacityColor: Color {
        CodexFloatTheme.freshnessTint(snapshot.freshness, attention: snapshot.attention)
    }

    private var capacityGradient: LinearGradient {
        LinearGradient(
            colors: [
                capacityColor.opacity(0.95),
                capacityColor.opacity(0.72)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var contentOnFill: Bool {
        fillFraction >= 0.28
    }

    private var showsRemainingLabel: Bool {
        snapshot.remainingPercent != nil && snapshot.freshness != .error && snapshot.freshness != .loading
    }

    private var accessibilityLabel: String {
        if let remaining = snapshot.remainingPercent {
            return "\(CodexFloatTheme.productName) 剩余 \(QuotaMath.formatPercent(remaining))"
        }
        return snapshot.statusMessage ?? CodexFloatTheme.productName
    }

    private var accessibilityValue: String {
        switch snapshot.freshness {
        case .loading: return "正在读取"
        case .stale: return "可能不是最新"
        case .error: return snapshot.statusMessage ?? "错误"
        case .current: return "最新"
        }
    }
}
