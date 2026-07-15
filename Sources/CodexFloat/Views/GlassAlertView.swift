import SwiftUI

enum GlassAlertKind {
    case info
    case success
    case warning

    /// Soft disc behind the brand mark (warning tints orange; others stay Ocean Mist).
    var badgeFill: Color {
        switch self {
        case .info, .success:
            return CodexFloatTheme.brandRing.opacity(0.14)
        case .warning:
            return Color(nsColor: .systemOrange).opacity(0.16)
        }
    }
}

/// Compact Liquid Glass dialog: brand logo, title, body, single「好」button.
struct GlassAlertView: View {
    let title: String
    let message: String
    let kind: GlassAlertKind
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(kind.badgeFill)
                        .frame(width: 40, height: 40)
                    // Product mark instead of system checkmark.
                    CodexFloatLogoMarkV2(style: .darkOnLight)
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer(minLength: 0)
                Button(action: onConfirm) {
                    Text("好")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 7)
                        .background {
                            Capsule(style: .continuous)
                                .fill(CodexFloatTheme.brandRing)
                        }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 18)
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background {
            LiquidGlassBackground(
                cornerRadius: 18,
                emphasized: true,
                includesChrome: false
            )
        }
        .liquidGlassChrome(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            edgeWidth: 1,
            emphasized: true
        )
    }
}
