import AppKit
import SwiftUI
import CodexFloatCore

/// Collapsed edge widget: transparent liquid-glass capsule with capacity fill flush to the edge.
/// Text stays dark until fill is wide enough that white glyphs sit fully on the color band.
struct CompactWidgetView: View {
    let snapshot: QuotaSnapshot

    var body: some View {
        ZStack {
            // Layer 1 — transparent glass (not opaque wash).
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)

            // Layer 2 — soft top sheen only.
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            // Layer 3 — capacity fill from the leading edge (green / orange / red by remaining %).
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let filled = max(0, min(width, width * fillFraction))
                if filled > 0.5 {
                    // Leading-aligned solid band; clip to capsule via outer chrome.
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(capacityGradient)
                            .frame(width: filled, height: height)
                        Spacer(minLength: 0)
                    }
                    .frame(width: width, height: height, alignment: .leading)
                }
            }
            .allowsHitTesting(false)

            // Layer 4 — logo + percent centered in the capsule (both axes).
            // Freshness (stale/error) stays on the menu-bar pip + detail banner — not a chip on the capsule.
            HStack(spacing: 5) {
                CodexFloatLogoMarkV2(style: contentOnFill ? .whiteOnDark : .darkOnLight)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)

                percentageText
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: CodexFloatTheme.widgetSize.width, height: CodexFloatTheme.widgetSize.height)
        .liquidGlassChrome(
            shape: Capsule(style: .continuous),
            edgeWidth: 0.8,
            edgeOpacity: 0.08,
            elevation: .soft
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var percentageText: some View {
        Group {
            if let remaining = snapshot.remainingPercent, snapshot.freshness != .loading {
                Text(QuotaMath.formatPercent(remaining))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primaryLabelColor)
                    .shadow(color: labelShadow, radius: contentOnFill ? 0.5 : 0, x: 0, y: 0.5)
            } else {
                Text("—")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryLabelColor)
            }
        }
    }

    /// White glyphs only when fill is wide enough that logo + % sit inside the color band.
    private var contentOnFill: Bool {
        fillFraction >= 0.58
    }

    private var primaryLabelColor: Color {
        if contentOnFill {
            return .white
        }
        return Color(nsColor: .labelColor)
    }

    private var secondaryLabelColor: Color {
        if contentOnFill {
            return Color.white.opacity(0.9)
        }
        return Color(nsColor: .secondaryLabelColor)
    }

    private var labelShadow: Color {
        contentOnFill ? Color.black.opacity(0.2) : .clear
    }

    private var fillFraction: CGFloat {
        guard let remaining = snapshot.remainingPercent, snapshot.freshness != .loading else {
            return 0
        }
        return CGFloat(min(100, max(0, remaining)) / 100)
    }

    private var capacityColor: Color {
        // Always capacity bands from remaining % (green / orange / red), never yellow.
        CodexFloatTheme.capacityFillColor(
            freshness: snapshot.freshness,
            attention: snapshot.attention
        )
    }

    private var capacityGradient: LinearGradient {
        // Higher opacity so band color survives glass + wallpaper bleed-through.
        LinearGradient(
            colors: [
                capacityColor.opacity(0.98),
                capacityColor.opacity(0.90)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
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
