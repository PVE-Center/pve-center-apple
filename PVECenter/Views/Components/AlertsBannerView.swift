import SwiftUI

public struct AlertsBannerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let alerts: [SmartAlert]
    public let onSelectTab: (AppTab) -> Void
    @State private var isExpanded: Bool = true

    public init(alerts: [SmartAlert], onSelectTab: @escaping (AppTab) -> Void) {
        self.alerts = alerts
        self.onSelectTab = onSelectTab
    }

    private var subtitleColor: Color {
        #if os(tvOS)
        return DesignTokens.secondaryText(colorScheme, highContrast: true)
        #else
        return DesignTokens.secondaryText(colorScheme, highContrast: contrast == .increased)
        #endif
    }

    private func color(for severity: SmartAlert.Severity) -> Color {
        switch severity {
        case .critical: DesignTokens.critical(colorScheme)
        case .warning: DesignTokens.caution(colorScheme)
        case .info: DesignTokens.accent(accentTheme, colorScheme)
        }
    }

    private func icon(for severity: SmartAlert.Severity) -> String {
        switch severity {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    public var body: some View {
        if !alerts.isEmpty {
            let topSeverity = alerts.first(where: { $0.severity == .critical })?.severity
                ?? alerts.first(where: { $0.severity == .warning })?.severity
                ?? .info
            let accent = color(for: topSeverity)

            GlassCard(padding: 14, cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        if reduceMotion {
                            isExpanded.toggle()
                        } else {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                                isExpanded.toggle()
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: topSeverity))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(alerts.count) point\(alerts.count > 1 ? "s" : "") d'attention")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .lineLimit(1)
                                    .multilineTextAlignment(.leading)
                                if !isExpanded, let first = alerts.first {
                                    Text(first.title)
                                        .font(.caption)
                                        .foregroundStyle(subtitleColor)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(subtitleColor)
                        }
                        #if os(tvOS)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        #endif
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .cardButtonStyle(cornerRadius: 12)

                    if isExpanded {
                        #if os(tvOS)
                        let rowSpacing: CGFloat = 10
                        let hSpacing: CGFloat = 14
                        let hPadding: CGFloat = 16
                        let vPadding: CGFloat = 12
                        let rowMinHeight: CGFloat = 54
                        #else
                        let rowSpacing: CGFloat = 8
                        let hSpacing: CGFloat = 10
                        let hPadding: CGFloat = 12
                        let vPadding: CGFloat = 10
                        let rowMinHeight: CGFloat = 44
                        #endif

                        VStack(spacing: rowSpacing) {
                            ForEach(alerts) { alert in
                                let alertColor = color(for: alert.severity)
                                Button {
                                    onSelectTab(alert.targetTab)
                                } label: {
                                    HStack(spacing: hSpacing) {
                                        Image(systemName: icon(for: alert.severity))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(alertColor)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(alert.title)
                                                #if os(tvOS)
                                                .font(.subheadline.weight(.semibold))
                                                #else
                                                .font(.caption.weight(.semibold))
                                                #endif
                                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(alert.subtitle)
                                                #if os(tvOS)
                                                .font(.caption)
                                                #else
                                                .font(.caption2)
                                                #endif
                                                .foregroundStyle(subtitleColor)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "arrow.right")
                                            .foregroundStyle(subtitleColor)
                                            .font(.caption.weight(.semibold))
                                    }
                                    .padding(.horizontal, hPadding)
                                    .padding(.vertical, vPadding)
                                    .frame(minHeight: rowMinHeight)
                                    #if !os(tvOS)
                                    .background(
                                        DesignTokens.surfaceElevated(theme: accentTheme, colorScheme),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                    #endif
                                }
                                .cardButtonStyle(cornerRadius: 12)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Real-time Foreground / tvOS Live Alert Banner

public struct LiveAlertOverlayBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public let banner: InAppAlertBanner
    public let onAcknowledge: (() -> Void)?
    public let onMuteOneHour: (() -> Void)?
    public let onOpenDetails: (() -> Void)?
    public let onDismiss: () -> Void

    public init(
        banner: InAppAlertBanner,
        onAcknowledge: (() -> Void)? = nil,
        onMuteOneHour: (() -> Void)? = nil,
        onOpenDetails: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.banner = banner
        self.onAcknowledge = onAcknowledge
        self.onMuteOneHour = onMuteOneHour
        self.onOpenDetails = onOpenDetails
        self.onDismiss = onDismiss
    }

    private var accentColor: Color {
        if banner.isResolved {
            return DesignTokens.nominal(colorScheme)
        }
        switch banner.severity.lowercased() {
        case "warning":
            return DesignTokens.caution(colorScheme)
        case "info":
            return DesignTokens.accent(accentTheme, colorScheme)
        default:
            return DesignTokens.critical(colorScheme)
        }
    }

    private var symbolName: String {
        if banner.isResolved {
            return "checkmark.shield.fill"
        }
        switch banner.severity.lowercased() {
        case "warning":
            return "exclamationmark.triangle.fill"
        case "info":
            return "info.circle.fill"
        default:
            return "exclamationmark.octagon.fill"
        }
    }

    private var maxBannerWidth: CGFloat {
        #if os(tvOS)
        return 880
        #elseif os(macOS)
        return 580
        #else
        return 540
        #endif
    }

    private var cardPadding: CGFloat {
        #if os(tvOS)
        return 20
        #else
        return 14
        #endif
    }

    public var body: some View {
        GlassCard(padding: cardPadding, cornerRadius: 20, elevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbolName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(accentColor)
                        .frame(width: 34, height: 34)
                        .background(
                            accentColor.opacity(colorScheme == .light ? 0.14 : 0.18),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(banner.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 4)
                            Text(banner.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                        }

                        HStack(spacing: 6) {
                            StatusPill(
                                banner.serviceName,
                                color: accentColor,
                                systemImage: banner.isResolved ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right"
                            )
                            Text(banner.message)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme, highContrast: true))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                HStack(spacing: 12) {
                    if !banner.isResolved, let onAcknowledge {
                        Button(action: onAcknowledge) {
                            Label("Acquitter", systemImage: "checkmark.circle")
                                #if os(tvOS)
                                .font(.callout.weight(.semibold))
                                #else
                                .font(.caption.weight(.semibold))
                                #endif
                                .lineLimit(1)
                        }
                        .adaptivePillButtonStyle(tint: accentColor, prominent: true)
                        .adaptiveSmallControlSize()
                    }

                    if !banner.isResolved, banner.serviceId != nil, let onMuteOneHour {
                        Button(action: onMuteOneHour) {
                            Label("Sourdine 1h", systemImage: "bell.slash")
                                #if os(tvOS)
                                .font(.callout.weight(.semibold))
                                #else
                                .font(.caption.weight(.semibold))
                                #endif
                                .lineLimit(1)
                        }
                        .adaptivePillButtonStyle()
                        .adaptiveSmallControlSize()
                    }

                    if let onOpenDetails {
                        Button(action: onOpenDetails) {
                            Label("Incidents", systemImage: "list.bullet.rectangle")
                                #if os(tvOS)
                                .font(.callout.weight(.semibold))
                                #else
                                .font(.caption.weight(.semibold))
                                #endif
                                .lineLimit(1)
                        }
                        .adaptivePillButtonStyle()
                        .adaptiveSmallControlSize()
                    }

                    Spacer(minLength: 4)

                    Button(action: onDismiss) {
                        Label("Fermer", systemImage: "xmark")
                            #if os(tvOS)
                            .font(.callout.weight(.semibold))
                            #else
                            .font(.caption.weight(.semibold))
                            #endif
                            .lineLimit(1)
                    }
                    .adaptivePillButtonStyle()
                    .adaptiveSmallControlSize()
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accentColor.opacity(0.42), lineWidth: 1.2)
                .allowsHitTesting(false)
        )
        .frame(maxWidth: maxBannerWidth)
        .shadow(
            color: Color.black.opacity(colorScheme == .light ? 0.12 : 0.42),
            radius: 18,
            x: 0,
            y: 8
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82),
            value: banner.id
        )
    }
}

// MARK: - Live Sync Status Pill (WS / SSE / Demo)

public struct RealtimeSyncPill: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme
    public let isDemoMode: Bool
    public let state: RealtimeConnectionState
    public let activeIncidentsCount: Int

    public init(
        isDemoMode: Bool,
        state: RealtimeConnectionState,
        activeIncidentsCount: Int = 0
    ) {
        self.isDemoMode = isDemoMode
        self.state = state
        self.activeIncidentsCount = activeIncidentsCount
    }

    private var pillLabel: String {
        if isDemoMode { return "Demo" }
        switch state {
        case .connectedWebSocket: return "WS"
        case .connectedSSE: return "SSE"
        case .connecting, .reconnecting: return "Sync"
        case .disconnected: return "Local"
        }
    }

    private var pillSymbol: String {
        if isDemoMode { return "sparkles" }
        switch state {
        case .connectedWebSocket: return "bolt.horizontal.fill"
        case .connectedSSE: return "antenna.radiowaves.left.and.right"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "wifi.slash"
        }
    }

    private var pillColor: Color {
        if isDemoMode {
            return .indigo
        }
        switch state {
        case .connectedWebSocket:
            return DesignTokens.nominal(colorScheme)
        case .connectedSSE:
            return DesignTokens.accent(accentTheme, colorScheme)
        case .connecting, .reconnecting:
            return DesignTokens.caution(colorScheme)
        case .disconnected:
            return DesignTokens.secondaryText(colorScheme)
        }
    }

    public var body: some View {
        HStack(spacing: 6) {
            StatusPill(pillLabel, color: pillColor, systemImage: pillSymbol)
            if activeIncidentsCount > 0 {
                StatusPill(
                    "\(activeIncidentsCount)",
                    color: DesignTokens.critical(colorScheme),
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isDemoMode
                ? "Mode Démo actif"
                : "Synchronisation temps réel : \(state.label)\(activeIncidentsCount > 0 ? ", \(activeIncidentsCount) incident actif" : "")"
        )
    }
}
