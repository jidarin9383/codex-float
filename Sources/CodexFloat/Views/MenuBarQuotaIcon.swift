import AppKit
import SwiftUI
import CodexFloatCore

/// Menu bar: template monochrome brand mark + live remaining percentage.
///
/// `MenuBarExtra` is unreliable with multi-color `Canvas` views, so the glyph is a
/// pure black template `NSImage`. Drawing uses **top-left origin** (`flipped: true`)
/// so the float ground arc stays at the bottom (matching the SVG brand mark).
struct MenuBarQuotaIcon: View {
    let snapshot: QuotaSnapshot

    var body: some View {
        HStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: Self.templateLogo(remainingPercent: visibleRemainingPercent))
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)

                // Freshness pip stays outside the template image so color remains visible.
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
                } else if snapshot.freshness == .stale {
                    Circle()
                        .fill(Color(nsColor: .systemYellow))
                        .frame(width: 5, height: 5)
                        .offset(x: 1, y: 1)
                }
            }
            .frame(width: 16, height: 16)

            Text(percentLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        QuotaAccessibility.menuBarLabel(
            productName: CodexFloatTheme.productName,
            snapshot: snapshot
        )
    }

    private var visibleRemainingPercent: Double? {
        snapshot.freshness == .loading ? nil : snapshot.remainingPercent
    }

    /// Compact text beside the glyph (e.g. `93%`, or placeholders while loading/unknown).
    private var percentLabel: String {
        if snapshot.freshness == .loading {
            return "…"
        }
        if let remaining = snapshot.remainingPercent {
            return QuotaMath.formatPercent(remaining)
        }
        return "—"
    }

    /// Black-on-clear 18×18 template matching brand silhouette with a live quota arc.
    /// Coordinates match `Assets/Brand/v2/menubar-template.svg` (y grows downward).
    private static func templateLogo(remainingPercent: Double?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(true)
            ctx.setAllowsAntialiasing(true)
            NSColor.black.set()

            // SVG center: orb sits above the float ground.
            let center = CGPoint(x: 9, y: 7.75)
            let radius: CGFloat = 5.55

            // Outer track
            let track = NSBezierPath(
                ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            )
            track.lineWidth = 1.15
            track.lineCapStyle = .round
            track.stroke()

            // Remaining progress starts at 12 o'clock, sweeps clockwise (battery-like remaining).
            if let remainingPercent {
                let fraction = min(1, max(0, remainingPercent / 100))
                if fraction > 0 {
                    let progress = NSBezierPath()
                    if fraction >= 0.999 {
                        progress.appendOval(
                            in: CGRect(
                                x: center.x - radius,
                                y: center.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                        )
                    } else {
                        // In flipped (y-down) view: 90° is top; clockwise decreases angle in AppKit.
                        progress.appendArc(
                            withCenter: center,
                            radius: radius,
                            startAngle: 90,
                            endAngle: 90 - (360 * fraction),
                            clockwise: true
                        )
                    }
                    progress.lineWidth = 1.75
                    progress.lineCapStyle = .round
                    progress.stroke()
                }
            }

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

            // Float ground — bottom arc under the orb (SVG y≈15.15 of 18).
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
    }
}
