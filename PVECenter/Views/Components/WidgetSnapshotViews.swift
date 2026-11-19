import Foundation
import os
import SwiftUI

// MARK: - WidgetKit-Ready Glanceable Telemetry Snapshot Model

/// Lightweight snapshot of live Proxmox node telemetry & alert status shared
/// with future WidgetKit Home Screen / Lock Screen extensions and glanceable previews.
public struct TelemetryWidgetSnapshot: Codable, Sendable, Equatable {
    public let updatedAt: Date
    public let serverName: String
    public let nodeName: String
    public let online: Bool
    public let cpuPct: Double
    public let memPct: Double
    public let runningGuests: Int
    public let totalGuests: Int
    public let activeIncidentsCount: Int
    public let latestIncidentTitle: String?

    public init(
        updatedAt: Date = Date(),
        serverName: String,
        nodeName: String,
        online: Bool,
        cpuPct: Double,
        memPct: Double,
        runningGuests: Int,
        totalGuests: Int,
        activeIncidentsCount: Int,
        latestIncidentTitle: String? = nil
    ) {
        self.updatedAt = updatedAt
        self.serverName = serverName
        self.nodeName = nodeName
        self.online = online
        self.cpuPct = cpuPct
        self.memPct = memPct
        self.runningGuests = runningGuests
        self.totalGuests = totalGuests
        self.activeIncidentsCount = activeIncidentsCount
        self.latestIncidentTitle = latestIncidentTitle
    }

    public static let placeholder = TelemetryWidgetSnapshot(
        updatedAt: Date(),
        serverName: "Homelab PVE",
        nodeName: "pve-node-01",
        online: true,
        cpuPct: 23.8,
        memPct: 43.8,
        runningGuests: 4,
        totalGuests: 5,
        activeIncidentsCount: 0,
        latestIncidentTitle: nil
    )
}

// MARK: - Thread-Safe Snapshot Persistence (Caches, UserDefaults & App Group)

/// Thread-safe (`Sendable`) JSON persistence store for `TelemetryWidgetSnapshot`.
/// Writes atomically to the Caches directory and `UserDefaults`, and optionally mirrors
/// to an App Group container when `appGroupIdentifier` is configured.
public struct TelemetrySnapshotStore: Sendable {
    public static let shared = TelemetrySnapshotStore()
    public static let defaultAppGroupIdentifier = "group.io.ac.pvepanel.app"
    public static let defaultUserDefaultsKey = "pve_center_telemetry_widget_snapshot_v1"
    public static let defaultFileName = "telemetry-widget-snapshot.json"

    private static let ioLock = OSAllocatedUnfairLock<Void>(initialState: ())

    public let appGroupIdentifier: String?
    public let userDefaultsKey: String
    public let fileName: String

    public init(
        appGroupIdentifier: String? = nil,
        userDefaultsKey: String = TelemetrySnapshotStore.defaultUserDefaultsKey,
        fileName: String = TelemetrySnapshotStore.defaultFileName
    ) {
        let trimmedGroup = appGroupIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appGroupIdentifier = (trimmedGroup?.isEmpty == false) ? trimmedGroup : nil
        self.userDefaultsKey = userDefaultsKey
        self.fileName = fileName
    }

    @discardableResult
    public nonisolated func save(_ snapshot: TelemetryWidgetSnapshot) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            return false
        }

        return Self.ioLock.withLock { _ in
            var wroteAny = false

            if let cachesURL = cachesSnapshotURL() {
                do {
                    let parent = cachesURL.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                    try data.write(to: cachesURL, options: [.atomic])
                    wroteAny = true
                } catch {
                    // Best-effort Caches write; fallback to UserDefaults below.
                }
            }

            if let groupID = appGroupIdentifier {
                if let groupURL = appGroupSnapshotURL(groupID: groupID) {
                    try? data.write(to: groupURL, options: [.atomic])
                }
                if let groupDefaults = UserDefaults(suiteName: groupID) {
                    groupDefaults.set(data, forKey: userDefaultsKey)
                    wroteAny = true
                }
            }

            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            wroteAny = true
            return wroteAny
        }
    }

    public nonisolated func load() -> TelemetryWidgetSnapshot? {
        guard let data = loadRawJSON() else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TelemetryWidgetSnapshot.self, from: data)
    }

    public nonisolated func loadRawJSON() -> Data? {
        Self.ioLock.withLock { _ in
            if let groupID = appGroupIdentifier,
               let groupURL = appGroupSnapshotURL(groupID: groupID),
               let data = try? Data(contentsOf: groupURL) {
                return data
            }

            if let cachesURL = cachesSnapshotURL(),
               let data = try? Data(contentsOf: cachesURL) {
                return data
            }

            if let groupID = appGroupIdentifier,
               let groupDefaults = UserDefaults(suiteName: groupID),
               let data = groupDefaults.data(forKey: userDefaultsKey) {
                return data
            }

            return UserDefaults.standard.data(forKey: userDefaultsKey)
        }
    }

    public nonisolated func clear() {
        Self.ioLock.withLock { _ in
            if let cachesURL = cachesSnapshotURL() {
                try? FileManager.default.removeItem(at: cachesURL)
            }
            if let groupID = appGroupIdentifier {
                if let groupURL = appGroupSnapshotURL(groupID: groupID) {
                    try? FileManager.default.removeItem(at: groupURL)
                }
                UserDefaults(suiteName: groupID)?.removeObject(forKey: userDefaultsKey)
            }
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }

    private nonisolated func cachesSnapshotURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PVECenter", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private nonisolated func appGroupSnapshotURL(groupID: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }
}

// MARK: - Glanceable Cider Liquid Glass Telemetry Widget Preview

/// SwiftUI glanceable telemetry view styled with Cider Liquid Glass design tokens,
/// ready for WidgetKit timelines and cross-platform inline previews (iOS, macOS, tvOS).
public struct GlanceableNodeWidgetView: View {
    public let snapshot: TelemetryWidgetSnapshot
    public let compact: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    public init(snapshot: TelemetryWidgetSnapshot, compact: Bool = false) {
        self.snapshot = snapshot
        self.compact = compact
    }

    private var cardPadding: CGFloat {
        #if os(tvOS)
        return compact ? 18 : 22
        #else
        return compact ? 12 : 16
        #endif
    }

    private var barHeight: CGFloat {
        #if os(tvOS)
        return 9
        #else
        return compact ? 6 : 7
        #endif
    }

    public var body: some View {
        let accent = DesignTokens.accent(accentTheme, colorScheme)
        let secondaryAccent = DesignTokens.secondaryAccent(accentTheme, colorScheme)
        let nominal = DesignTokens.nominal(colorScheme)
        let critical = DesignTokens.critical(colorScheme)

        GlassCard(padding: cardPadding, cornerRadius: compact ? 18 : 20, elevated: true) {
            VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "server.rack")
                        .font(compact ? .subheadline.weight(.bold) : .headline.weight(.bold))
                        .foregroundStyle(accent)
                        .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                        .background(
                            DesignTokens.surfaceElevated(theme: accentTheme, colorScheme),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.serverName)
                            #if os(tvOS)
                            .font(.callout.weight(.bold))
                            #else
                            .font(.subheadline.weight(.bold))
                            #endif
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            .lineLimit(1)
                        Text(snapshot.nodeName)
                            #if os(tvOS)
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            #else
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            #endif
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    StatusPill(
                        snapshot.online ? "En ligne" : "Hors ligne",
                        color: snapshot.online ? nominal : critical,
                        systemImage: snapshot.online ? "checkmark.circle.fill" : "xmark.octagon.fill"
                    )
                    .lineLimit(1)
                    .fixedSize()
                }

                HStack(spacing: 12) {
                    metricGauge(
                        label: "CPU",
                        percentage: snapshot.cpuPct,
                        tint: accent
                    )
                    metricGauge(
                        label: "RAM",
                        percentage: snapshot.memPct,
                        tint: secondaryAccent
                    )
                }

                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption2)
                            .foregroundStyle(accent)
                        Text("\(snapshot.runningGuests)/\(snapshot.totalGuests) invités")
                            #if os(tvOS)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            #else
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            #endif
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                    }
                    .lineLimit(1)

                    Spacer(minLength: 6)

                    if snapshot.activeIncidentsCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .font(.caption2)
                                .foregroundStyle(critical)
                            Text(
                                snapshot.latestIncidentTitle?.isEmpty == false
                                    ? "\(snapshot.activeIncidentsCount) • \(snapshot.latestIncidentTitle!)"
                                    : "\(snapshot.activeIncidentsCount) incident\(snapshot.activeIncidentsCount > 1 ? "s" : "")"
                            )
                            #if os(tvOS)
                            .font(.caption.weight(.semibold))
                            #else
                            .font(.caption2.weight(.semibold))
                            #endif
                            .foregroundStyle(critical)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.caption2)
                                .foregroundStyle(nominal)
                            Text("Nominal")
                                #if os(tvOS)
                                .font(.caption.weight(.semibold))
                                #else
                                .font(.caption2.weight(.semibold))
                                #endif
                                .foregroundStyle(nominal)
                        }
                        .lineLimit(1)

                        Text(snapshot.updatedAt, style: .time)
                            #if os(tvOS)
                            .font(.system(.caption2, design: .monospaced))
                            #else
                            .font(.system(size: 10, design: .monospaced))
                            #endif
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private func metricGauge(label: String, percentage: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    #if os(tvOS)
                    .font(.caption.weight(.semibold))
                    #else
                    .font(.caption2.weight(.semibold))
                    #endif
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                Spacer(minLength: 4)
                Text(String(format: "%.0f %%", percentage))
                    #if os(tvOS)
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    #else
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    #endif
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
            }
            .lineLimit(1)
            UsageProgressBar(percentage: percentage, tint: tint, height: barHeight)
        }
    }

    private var accessibilitySummary: String {
        let stateLabel = snapshot.online ? "en ligne" : "hors ligne"
        let incidentLabel: String
        if snapshot.activeIncidentsCount > 0 {
            incidentLabel = "\(snapshot.activeIncidentsCount) incident actif"
        } else {
            incidentLabel = "aucun incident actif"
        }
        return "\(snapshot.serverName), nœud \(snapshot.nodeName), \(stateLabel), CPU \(Int(snapshot.cpuPct.rounded())) pourcent, RAM \(Int(snapshot.memPct.rounded())) pourcent, \(snapshot.runningGuests) invités actifs sur \(snapshot.totalGuests), \(incidentLabel)."
    }
}
