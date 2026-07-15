import SwiftUI
import CodexFloatCore

enum CodexFloatTheme {
    static let productName = "Codex Float"
    /// Compact float capsule — logo + percent only.
    static let widgetSize = CGSize(width: 92, height: 36)
    /// Collapsed detail (reset-credit list folded).
    static let detailSize = CGSize(width: 320, height: 372)
    /// One expanded reset-credit row (divider + line).
    static let detailResetRowHeight: CGFloat = 36
    /// Transparent margin so shape-following shadows are not clipped by the NSPanel rect.
    static let panelShadowBleed: CGFloat = 28
    /// Tahoe-forward continuous radii.
    static let widgetRadius: CGFloat = 18
    static let detailRadius: CGFloat = 22
    static let groupRadius: CGFloat = 14
    static let baseUnit: CGFloat = 4

    static func detailSize(resetRowsVisible: Int) -> CGSize {
        let extra = CGFloat(max(0, resetRowsVisible)) * detailResetRowHeight
        return CGSize(width: detailSize.width, height: detailSize.height + extra)
    }

    static func contentSize(expanded: Bool, resetRowsVisible: Int = 0) -> CGSize {
        expanded ? detailSize(resetRowsVisible: resetRowsVisible) : widgetSize
    }

    static func panelSize(expanded: Bool, resetRowsVisible: Int = 0) -> CGSize {
        let content = contentSize(expanded: expanded, resetRowsVisible: resetRowsVisible)
        let pad = panelShadowBleed * 2
        return CGSize(width: content.width + pad, height: content.height + pad)
    }

    // MARK: Brand — Ocean Mist (frozen)
    /// Deep ink for marks / primary text accents.
    static let brandInk = Color(red: 0x17 / 255, green: 0x32 / 255, blue: 0x38 / 255)
    /// Progress ring / brand accent.
    static let brandRing = Color(red: 0x3D / 255, green: 0x7A / 255, blue: 0x86 / 255)
    static let brandRingDeep = Color(red: 0x2A / 255, green: 0x5A / 255, blue: 0x64 / 255)
    /// Soft glass fill.
    static let brandGlass = Color(red: 0xA9 / 255, green: 0xC8 / 255, blue: 0xCF / 255)
    static let brandMist = Color(red: 0xE6 / 255, green: 0xF2 / 255, blue: 0xF4 / 255)

    /// Battery-like quota colors: green >50%, orange 20–50%, red ≤20%.
    /// Kept vivid so the floating widget fill reads clearly through glass.
    static func attentionColor(_ attention: QuotaAttention) -> Color {
        switch attention {
        case .healthy:
            return Color(nsColor: .systemGreen)
        case .attention:
            return Color(nsColor: .systemOrange)
        case .critical:
            return Color(nsColor: .systemRed)
        case .unknown:
            return Color(nsColor: .secondaryLabelColor)
        }
    }

    static func freshnessTint(_ freshness: QuotaFreshness, attention: QuotaAttention) -> Color {
        switch freshness {
        case .stale:
            return Color(nsColor: .systemYellow)
        case .error, .loading:
            return Color(nsColor: .secondaryLabelColor)
        case .current:
            return attentionColor(attention)
        }
    }
}

/// Dual-tone edge so glass stays legible on white and dark desktops.
struct GlassEdgeStroke<S: InsettableShape>: View {
    var shape: S
    var lineWidth: CGFloat = 1
    /// Outer hairline strength (lower = less “black rim”).
    var edgeOpacity: Double = 0.10

    var body: some View {
        ZStack {
            // Outer: soft dark hairline — separation on light/white wallpapers.
            shape.strokeBorder(Color.black.opacity(edgeOpacity), lineWidth: lineWidth)
            // Inner: light specular — reads on dark wallpapers.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.72),
                        Color.white.opacity(0.28),
                        Color.white.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: max(0.55, lineWidth * 0.6)
            )
        }
        .allowsHitTesting(false)
    }
}

/// Soft Liquid Glass elevation that follows **rounded silhouette**, not a rectangle.
///
/// Materials often composite as rectangular layers. Applying `.shadow` directly on them
/// casts a box shadow. Flatten with `compositingGroup()` *after* clipping so the
/// shadow uses the rounded alpha mask (Apple-style floating glass).
struct LiquidGlassElevation: ViewModifier {
    enum Style {
        /// Floating widget — airy, no heavy black pad under the capsule.
        case soft
        /// Detail panel — slightly more lift.
        case regular
        case emphasized
    }

    var style: Style = .regular

    func body(content: Content) -> some View {
        // Flatten clipped glass into one bitmap with correct rounded alpha, then shade.
        let flat = content.compositingGroup()
        switch style {
        case .soft:
            // Single diffuse lift — avoids the “black base plate” look on white desktops.
            flat
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
        case .regular:
            flat
                .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 0.5)
                .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
        case .emphasized:
            flat
                .shadow(color: Color.black.opacity(0.04), radius: 1.5, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        }
    }
}

extension View {
    /// Clip to `shape`, then cast a soft multi-layer shadow that follows that contour.
    func liquidGlassChrome<S: InsettableShape>(
        shape: S,
        edgeWidth: CGFloat = 0.95,
        edgeOpacity: Double = 0.10,
        elevation: LiquidGlassElevation.Style = .regular,
        emphasized: Bool = false
    ) -> some View {
        let style: LiquidGlassElevation.Style = emphasized ? .emphasized : elevation
        return self
            .clipShape(shape)
            .overlay {
                GlassEdgeStroke(shape: shape, lineWidth: edgeWidth, edgeOpacity: edgeOpacity)
            }
            .modifier(LiquidGlassElevation(style: style))
    }

    func liquidGlassElevation(emphasized: Bool = false) -> some View {
        modifier(LiquidGlassElevation(style: emphasized ? .emphasized : .regular))
    }
}

/// Liquid Glass surface (macOS Tahoe-inspired):
/// material + specular sheen. Clip + edge + elevation applied by the host view.
struct LiquidGlassBackground: View {
    var cornerRadius: CGFloat
    var emphasized: Bool = false
    /// Apply clip, dual-tone edge, and shape-following shadow (default true).
    var includesChrome: Bool = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let glass = shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(emphasized ? 0.40 : 0.32),
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.plusLighter)
            }
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.025),
                                Color.clear,
                                Color.primary.opacity(0.035)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

        if includesChrome {
            glass.liquidGlassChrome(
                shape: shape,
                edgeWidth: emphasized ? 1.05 : 0.95,
                emphasized: emphasized
            )
        } else {
            glass
        }
    }
}

struct GlassGroupBackground: View {
    var cornerRadius: CGFloat = CodexFloatTheme.groupRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
            }
    }
}
