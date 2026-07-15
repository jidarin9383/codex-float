import SwiftUI

/// Shared Codex Float brand mark: code chip + float arc.
/// Same silhouette as Assets/Brand marks — used in-app without raster assets.
struct CodexFloatLogoMark: View {
    enum Style {
        /// Menu bar template: monochrome, system-tinted.
        case template
        /// White chip for dark / glass surfaces.
        case whiteOnDark
        /// Dark chip for light surfaces.
        case darkOnLight
        /// Full app-icon-like tile.
        case appTile
    }

    var style: Style = .template
    var showsFloatArc: Bool = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                if style == .appTile {
                    RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.11, green: 0.11, blue: 0.12),
                                    Color(red: 0.04, green: 0.04, blue: 0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                mark(in: s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mark(in s: CGFloat) -> some View {
        let chipFill = chipFillColor
        let ink = inkColor
        let arc = arcColor

        ZStack {
            // Code chip
            RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                .fill(chipFill)
                .frame(width: s * 0.62, height: s * 0.48)
                .offset(y: showsFloatArc ? -s * 0.08 : 0)

            // Code strokes + caret
            VStack(alignment: .leading, spacing: s * 0.055) {
                Capsule().fill(ink).frame(width: s * 0.20, height: s * 0.055)
                Capsule().fill(ink).frame(width: s * 0.32, height: s * 0.055)
                Capsule().fill(ink).frame(width: s * 0.24, height: s * 0.055)
            }
            .offset(x: -s * 0.05, y: showsFloatArc ? -s * 0.08 : 0)

            // Agent caret
            CaretShape()
                .fill(ink)
                .frame(width: s * 0.12, height: s * 0.16)
                .offset(x: s * 0.16, y: showsFloatArc ? -s * 0.08 : 0)

            if showsFloatArc {
                // Float arc
                FloatArcShape()
                    .stroke(arc, style: StrokeStyle(lineWidth: max(1.2, s * 0.07), lineCap: .round))
                    .frame(width: s * 0.55, height: s * 0.18)
                    .offset(y: s * 0.30)

                Circle()
                    .fill(style == .template ? arc : Color(red: 0.06, green: 0.64, blue: 0.50))
                    .frame(width: s * 0.08, height: s * 0.08)
                    .offset(y: s * 0.36)
            }
        }
    }

    private var chipFillColor: Color {
        switch style {
        case .template:
            return Color.primary
        case .whiteOnDark:
            return .white
        case .darkOnLight, .appTile:
            return Color(red: 0.07, green: 0.09, blue: 0.15)
        }
    }

    private var inkColor: Color {
        switch style {
        case .template:
            // Template mark is solid silhouette via MenuBarLogoShape; this style
            // keeps chip solid primary without reverse-ink strokes.
            return Color(nsColor: .windowBackgroundColor)
        case .whiteOnDark:
            return Color(red: 0.04, green: 0.04, blue: 0.05)
        case .darkOnLight, .appTile:
            return .white
        }
    }

    private var arcColor: Color {
        switch style {
        case .template:
            return Color.primary
        case .whiteOnDark:
            return .white
        case .darkOnLight:
            return Color(red: 0.07, green: 0.09, blue: 0.15)
        case .appTile:
            return .white
        }
    }
}

/// Menu bar logo: template silhouette optimized for 16–18 pt.
/// Uses a single-color filled path so macOS can render it as a template image.
struct MenuBarLogoIcon: View {
    var body: some View {
        // Render as template-friendly monochrome shape.
        MenuBarLogoShape()
            .fill(Color.primary)
            .frame(width: 18, height: 18)
            .accessibilityLabel("Codex Float")
    }
}

/// Unified filled silhouette for the menu bar (chip + caret + arc + node).
struct MenuBarLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        // Chip
        let chip = CGRect(x: w * 0.16, y: h * 0.08, width: w * 0.68, height: h * 0.52)
        path.addPath(Path(roundedRect: chip, cornerRadius: w * 0.14, style: .continuous))

        // Caret on the right of chip (filled triangle)
        var caret = Path()
        let cx = w * 0.70
        let cy = h * 0.34
        caret.move(to: CGPoint(x: cx - w * 0.04, y: cy - h * 0.10))
        caret.addLine(to: CGPoint(x: cx + w * 0.10, y: cy))
        caret.addLine(to: CGPoint(x: cx - w * 0.04, y: cy + h * 0.10))
        caret.closeSubpath()
        path.addPath(caret)

        // Float arc (stroked as thick filled band via adjacent curves approx with capsule)
        // Approximate arc with a few rounded rects / thick stroke converted to path.
        let arc = FloatArcShape().path(in: CGRect(
            x: w * 0.18,
            y: h * 0.62,
            width: w * 0.64,
            height: h * 0.22
        ))
        // Stroke to fill manually
        let stroked = arc.cgPath.copy(
            strokingWithWidth: max(1.4, w * 0.09),
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 4
        )
        path.addPath(Path(stroked))

        // Node under arc
        let nodeR = w * 0.055
        path.addEllipse(in: CGRect(
            x: w * 0.5 - nodeR,
            y: h * 0.84 - nodeR,
            width: nodeR * 2,
            height: nodeR * 2
        ))

        return path
    }
}

struct CaretShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct FloatArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}
