import SwiftUI

/// Brand **v2.3 — Float Glass**:
/// outer progress ring (~1/3) around the orb, center `>`, soft ground.
struct CodexFloatLogoMarkV2: View {
    enum Style {
        case template
        case whiteOnDark
        case darkOnLight
        case appTile
    }

    var style: Style = .template

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                if style == .appTile {
                    RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.97, green: 0.98, blue: 0.99),
                                    Color(red: 0.83, green: 0.87, blue: 0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.75), lineWidth: 0.8)
                        }
                }

                Ellipse()
                    .fill(groundColor.opacity(style == .template ? 1 : 0.2))
                    .frame(width: s * 0.46, height: s * 0.09)
                    .offset(y: s * 0.38)

                // OUTER progress
                Circle()
                    .stroke(ink.opacity(style == .template ? 0.35 : 0.12), lineWidth: max(1.2, s * 0.07))
                    .frame(width: s * 0.72, height: s * 0.72)
                    .offset(y: -s * 0.06)

                Circle()
                    .trim(from: 0, to: 1.0 / 3.0)
                    .stroke(
                        progressColor,
                        style: StrokeStyle(lineWidth: max(1.35, s * 0.08), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: s * 0.72, height: s * 0.72)
                    .offset(y: -s * 0.06)

                Circle()
                    .fill(orbFill)
                    .frame(width: s * 0.52, height: s * 0.52)
                    .overlay {
                        Circle()
                            .strokeBorder(orbStroke, lineWidth: max(0.9, s * 0.035))
                    }
                    .offset(y: -s * 0.06)

                CodeCaretShape()
                    .stroke(ink, style: StrokeStyle(lineWidth: max(1.4, s * 0.075), lineCap: .round, lineJoin: .round))
                    .frame(width: s * 0.18, height: s * 0.22)
                    .offset(y: -s * 0.06)

                if style != .template {
                    Ellipse()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: s * 0.12, height: s * 0.07)
                        .rotationEffect(.degrees(-28))
                        .offset(x: -s * 0.08, y: -s * 0.14)
                }

                FloatArcShape()
                    .stroke(arcColor, style: StrokeStyle(lineWidth: max(1.2, s * 0.06), lineCap: .round))
                    .frame(width: s * 0.52, height: s * 0.15)
                    .offset(y: s * 0.34)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var orbFill: Color {
        switch style {
        case .template: return .clear
        case .whiteOnDark: return Color.white.opacity(0.95)
        case .darkOnLight, .appTile: return CodexFloatTheme.brandMist
        }
    }

    private var orbStroke: Color {
        switch style {
        case .template: return Color.primary
        case .whiteOnDark: return Color.white.opacity(0.45)
        case .darkOnLight, .appTile: return Color.white.opacity(0.9)
        }
    }

    private var ink: Color {
        switch style {
        case .template: return Color.primary
        default: return CodexFloatTheme.brandInk
        }
    }

    private var progressColor: Color {
        switch style {
        case .template: return Color.primary
        default: return CodexFloatTheme.brandRing
        }
    }

    private var groundColor: Color {
        switch style {
        case .template: return Color.primary
        default: return CodexFloatTheme.brandRing.opacity(0.85)
        }
    }

    private var arcColor: Color {
        switch style {
        case .template: return Color.primary
        case .whiteOnDark: return Color.white.opacity(0.75)
        case .darkOnLight, .appTile: return CodexFloatTheme.brandRing.opacity(0.55)
        }
    }
}

/// 18pt menu bar icon — layered strokes (not one Path with uniform width).
struct MenuBarLogoIconV2: View {
    var body: some View {
        MenuBarLogoGlyphV2()
            .frame(width: 18, height: 18)
            .accessibilityLabel("Codex Float")
    }
}

/// Pixel-faithful match to `Assets/Brand/v2/menubar-template.svg` (viewBox 18×18).
/// Solid disc (one circle) + outer progress + `>` cutout + float ground.
struct MenuBarLogoGlyphV2: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 18
            let t = CGAffineTransform(scaleX: scale, y: scale)
            let ink = Color.primary
            let center = CGPoint(x: 9, y: 7.75)

            // Outer track
            var track = Path()
            track.addEllipse(in: CGRect(x: center.x - 5.55, y: center.y - 5.55, width: 11.1, height: 11.1))
            context.stroke(
                track.applying(t),
                with: .color(ink),
                style: StrokeStyle(lineWidth: 1.15 * scale, lineCap: .round)
            )

            // Progress ~1/3
            var progress = Path()
            progress.addArc(
                center: center,
                radius: 5.55,
                startAngle: .degrees(-90),
                endAngle: .degrees(30),
                clockwise: false
            )
            context.stroke(
                progress.applying(t),
                with: .color(ink),
                style: StrokeStyle(lineWidth: 1.55 * scale, lineCap: .round)
            )

            // Solid disc with `>` hole (even-odd) — reads as one filled circle
            var combined = Path()
            combined.addEllipse(in: CGRect(
                x: (center.x - 3.7) * scale,
                y: (center.y - 3.7) * scale,
                width: 7.4 * scale,
                height: 7.4 * scale
            ))
            var hole = Path()
            hole.move(to: CGPoint(x: 7.25 * scale, y: 6.05 * scale))
            hole.addLine(to: CGPoint(x: 10.55 * scale, y: 7.75 * scale))
            hole.addLine(to: CGPoint(x: 7.25 * scale, y: 9.45 * scale))
            hole.addLine(to: CGPoint(x: 7.25 * scale, y: 8.55 * scale))
            hole.addLine(to: CGPoint(x: 9.15 * scale, y: 7.75 * scale))
            hole.addLine(to: CGPoint(x: 7.25 * scale, y: 6.95 * scale))
            hole.closeSubpath()
            combined.addPath(hole)
            context.fill(combined, with: .color(ink), style: FillStyle(eoFill: true))

            // Float ground
            var ground = Path()
            ground.move(to: CGPoint(x: 4.4, y: 15.15))
            ground.addQuadCurve(
                to: CGPoint(x: 13.6, y: 15.15),
                control: CGPoint(x: 9, y: 16.9)
            )
            context.stroke(
                ground.applying(t),
                with: .color(ink),
                style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round)
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct CodeCaretShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
