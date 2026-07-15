import AppKit
import SwiftUI
import CodexFloatCore

/// Menu bar uses a **template monochrome** app logo (system-tinted).
/// Accessibility still announces remaining quota.
///
/// Important: `MenuBarExtra` is unreliable with `Canvas` + multi-color SwiftUI views.
/// We rasterize a pure black 18×18 template `NSImage` so macOS always shows the glyph.
struct MenuBarQuotaIcon: View {
    let snapshot: QuotaSnapshot

    var body: some View {
        // Label gives the extra a stable identity; icon is the template image.
        Label {
            Text(CodexFloatTheme.productName)
        } icon: {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: Self.templateLogo)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)

                // Status pip only — kept outside the template image.
                if snapshot.freshness == .error {
                    Circle()
                        .fill(Color(nsColor: .systemOrange))
                        .frame(width: 5, height: 5)
                        .offset(x: 1, y: 1)
                } else if snapshot.freshness == .loading {
                    Circle()
                        .fill(Color.primary.opacity(0.45))
                        .frame(width: 4, height: 4)
                        .offset(x: 1, y: 1)
                }
            }
            .frame(width: 18, height: 18)
        }
        .labelStyle(.iconOnly)
        .frame(width: 22, height: 22)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let remaining = snapshot.remainingPercent, snapshot.freshness != .loading {
            return "\(CodexFloatTheme.productName) 剩余 \(QuotaMath.formatPercent(remaining))"
        }
        return snapshot.statusMessage ?? CodexFloatTheme.productName
    }

    /// Black-on-clear 18×18 template matching `Assets/Brand/v2/menubar-template.svg`.
    private static let templateLogo: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(true)
            ctx.setAllowsAntialiasing(true)
            NSColor.black.set()

            let scale: CGFloat = 1
            let center = CGPoint(x: 9 * scale, y: 7.75 * scale)

            // Outer track
            let track = NSBezierPath(
                ovalIn: CGRect(x: center.x - 5.55, y: center.y - 5.55, width: 11.1, height: 11.1)
            )
            track.lineWidth = 1.15
            track.lineCapStyle = .round
            track.stroke()

            // Progress ~1/3 from 12 o'clock clockwise to ~30°
            let progress = NSBezierPath()
            progress.appendArc(
                withCenter: center,
                radius: 5.55,
                startAngle: 90,   // AppKit: 0° = east, positive CCW; 90° = north
                endAngle: -30,    // ≈ 30° past east going clockwise from north ≈ 120° of arc
                clockwise: true
            )
            progress.lineWidth = 1.55
            progress.lineCapStyle = .round
            progress.stroke()

            // Solid disc with `>` hole (even-odd)
            let disc = NSBezierPath(
                ovalIn: CGRect(x: center.x - 3.7, y: center.y - 3.7, width: 7.4, height: 7.4)
            )
            let hole = NSBezierPath()
            hole.move(to: CGPoint(x: 7.25, y: 6.05))
            hole.line(to: CGPoint(x: 10.55, y: 7.75))
            hole.line(to: CGPoint(x: 7.25, y: 9.45))
            hole.line(to: CGPoint(x: 7.25, y: 8.55))
            hole.line(to: CGPoint(x: 9.15, y: 7.75))
            hole.line(to: CGPoint(x: 7.25, y: 6.95))
            hole.close()
            disc.append(hole)
            disc.windingRule = .evenOdd
            disc.fill()

            // Float ground
            let ground = NSBezierPath()
            ground.move(to: CGPoint(x: 4.4, y: 15.15))
            ground.curve(
                to: CGPoint(x: 13.6, y: 15.15),
                controlPoint1: CGPoint(x: 6.7, y: 16.55),
                controlPoint2: CGPoint(x: 11.3, y: 16.55)
            )
            ground.lineWidth = 1.2
            ground.lineCapStyle = .round
            ground.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }()
}
