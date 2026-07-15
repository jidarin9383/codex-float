import SwiftUI
import CodexFloatCore

/// Expanded floating detail. Collapse returns to the edge widget.
struct DetailPanelView: View {
    let snapshot: QuotaSnapshot
    var isResetListExpanded: Bool
    var canExpandResetList: Bool
    var onCollapse: () -> Void
    var onToggleResetList: () -> Void

    private var detailHeight: CGFloat {
        let rows = isResetListExpanded && canExpandResetList
            ? snapshot.resetOpportunities.filter { $0.expiresAt != nil }.count
            : 0
        return CodexFloatTheme.detailSize(resetRowsVisible: rows).height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            progressSection
            factsSection
            Spacer(minLength: 0)
            resetOpportunitySection
            if let message = snapshot.statusMessage, snapshot.freshness != .current {
                statusBanner(message)
            }
        }
        .padding(16)
        .frame(
            width: CodexFloatTheme.detailSize.width,
            height: detailHeight,
            alignment: .topLeading
        )
        .background {
            LiquidGlassBackground(
                cornerRadius: CodexFloatTheme.detailRadius,
                emphasized: true,
                includesChrome: false
            )
        }
        .liquidGlassChrome(
            shape: RoundedRectangle(cornerRadius: CodexFloatTheme.detailRadius, style: .continuous),
            edgeWidth: 1.05,
            emphasized: true
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CodexFloatLogoMarkV2(style: .darkOnLight)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(CodexFloatTheme.productName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Button(action: onCollapse) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6)
                                }
                        }
                }
                .buttonStyle(.plain)
                .help("收起")
                .accessibilityLabel("收起")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("本周剩余")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                heroPercentage
            }
        }
    }

    @ViewBuilder
    private var heroPercentage: some View {
        if let remaining = snapshot.remainingPercent, snapshot.freshness != .loading {
            Text(QuotaMath.formatPercent(remaining))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        } else {
            Text("—")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var progressSection: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                    }
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.95),
                                tint.opacity(0.75)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geo.size.width * progressFraction))
                    .shadow(color: tint.opacity(0.35), radius: 6, x: 0, y: 0)
            }
        }
        .frame(height: 9)
        .accessibilityLabel("剩余额度进度")
        .accessibilityValue(progressAccessibilityValue)
    }

    private var factsSection: some View {
        VStack(spacing: 0) {
            resetFactRow
            Divider().opacity(0.28)
            factRow(title: "当前套餐", value: snapshot.planType ?? "—")
            if snapshot.freshness == .stale {
                Divider().opacity(0.28)
                factRow(title: "状态", value: "可能不是最新")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background {
            GlassGroupBackground()
        }
    }

    private var resetFactRow: some View {
        HStack(alignment: .center) {
            Text("下次重置")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(resetDateValue)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let relative = resetRelativeValue {
                    Text(relative)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
    }

    private func factRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 36)
    }

    /// Summary always; expand control only when at least one credit has an expiry date.
    @ViewBuilder
    private var resetOpportunitySection: some View {
        let datedRows = snapshot.resetOpportunities.filter { $0.expiresAt != nil }
        let count = snapshot.resetOpportunityCount
            ?? (snapshot.resetOpportunities.isEmpty ? nil : snapshot.resetOpportunities.count)

        if let count, count > 0 {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("重置机会")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text("\(count) 次可用")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    if canExpandResetList {
                        Button(action: onToggleResetList) {
                            Image(systemName: isResetListExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .background {
                                    Circle()
                                        .fill(Color.primary.opacity(0.06))
                                }
                        }
                        .buttonStyle(.plain)
                        .help(isResetListExpanded ? "收起明细" : "展开明细")
                        .accessibilityLabel(isResetListExpanded ? "收起重置机会明细" : "展开重置机会明细")
                    }
                }
                .frame(minHeight: 36)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canExpandResetList else { return }
                    onToggleResetList()
                }

                if isResetListExpanded, canExpandResetList {
                    ForEach(datedRows) { item in
                        Divider().opacity(0.28)
                        HStack {
                            Text("第 \(item.index) 次")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Text(resetOpportunityDateLabel(item.expiresAt))
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 32)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "第 \(item.index) 次重置机会，\(resetOpportunityDateLabel(item.expiresAt))"
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                GlassGroupBackground()
            }
        } else if count == 0 {
            HStack {
                Text("重置机会")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("暂无")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                GlassGroupBackground()
            }
        }
    }

    private func resetOpportunityDateLabel(_ date: Date?) -> String {
        guard let date else { return "可用" }
        return ResetTimeFormatting.absoluteResetDateLabel(until: date, now: .now)
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.freshness == .stale ? "clock" : "exclamationmark.triangle.fill")
                .foregroundStyle(
                    snapshot.freshness == .stale
                        ? Color(nsColor: .systemYellow)
                        : Color(nsColor: .systemOrange)
                )
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background {
            GlassGroupBackground(cornerRadius: 12)
        }
    }

    private var resetDateValue: String {
        guard let resetsAt = snapshot.resetsAt else { return "—" }
        return ResetTimeFormatting.absoluteResetDateTimeLabel(until: resetsAt, now: .now)
    }

    private var resetRelativeValue: String? {
        guard let resetsAt = snapshot.resetsAt else { return nil }
        return ResetTimeFormatting.relativeResetLabel(until: resetsAt, now: .now)
    }

    private var tint: Color {
        CodexFloatTheme.freshnessTint(snapshot.freshness, attention: snapshot.attention)
    }

    private var progressFraction: CGFloat {
        guard let remaining = snapshot.remainingPercent else { return 0 }
        return CGFloat(min(1, max(0, remaining / 100)))
    }

    private var progressAccessibilityValue: String {
        guard let remaining = snapshot.remainingPercent else { return "未知" }
        return QuotaMath.formatPercent(remaining)
    }
}
