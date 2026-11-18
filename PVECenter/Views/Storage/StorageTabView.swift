#if canImport(Charts)
import Charts
#endif
import SwiftUI

private struct PoolSlice: Identifiable {
    let id: String
    let label: String
    let bytes: Double
    let color: Color
}

public struct StorageTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme
    @State private var showHealthyOnly = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var adaptiveColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 760), spacing: 24)]
        #elseif os(macOS)
        return [GridItem(.adaptive(minimum: 320), spacing: 12)]
        #else
        return [GridItem(.flexible())]
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return 12
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let ext = viewModel.pveOverview?.externalStorage {
                    poolChartCard(ext.pool)

                    if let ssd = ext.systemSsd {
                        systemSsdCard(ssd)
                    }

                    drivesSection(ext.drives)
                }

                if let storages = viewModel.pveOverview?.node.storages, !storages.isEmpty {
                    proxmoxDatastoresSection(storages)
                }
            }
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
            .padding(.vertical, DesignTokens.pageVerticalPadding)
        }
        #if os(tvOS)
        .contentMargins(.top, 18, for: .scrollContent)
        .contentMargins(.bottom, 32, for: .scrollContent)
        #else
        .contentMargins(.top, 8, for: .scrollContent)
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
        #endif
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: showHealthyOnly)
        #endif
    }

    private func poolChartCard(_ pool: MergerfsPoolInfo) -> some View {
        let teal = DesignTokens.accent(accentTheme, colorScheme)
        let usedColor = pool.usedPct >= 85 ? DesignTokens.caution(colorScheme) : teal
        let used = max(0, Double(pool.usedBytes))
        let avail = max(0, Double(pool.availBytes))
        let availSliceColor = colorScheme == .light
            ? Color(red: 0.067, green: 0.098, blue: 0.173).opacity(0.11)
            : DesignTokens.surfaceElevated(theme: accentTheme, colorScheme)
        let slices: [PoolSlice] = [
            PoolSlice(id: "used", label: "Utilisé", bytes: used, color: usedColor),
            PoolSlice(id: "avail", label: "Disponible", bytes: avail, color: availSliceColor),
        ]

        #if os(tvOS)
        let donutSize: CGFloat = 220
        let donutRowSpacing: CGFloat = 32
        #else
        let donutSize: CGFloat = 112
        let donutRowSpacing: CGFloat = 18
        #endif

        return GlassCard(padding: {
            #if os(tvOS)
            22
            #else
            16
            #endif
        }(), cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(pool.name, systemImage: "square.stack.3d.up.fill")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            .lineLimit(1)
                        Text("\(pool.fstype) • \(pool.policy) • \(pool.drivesCount) disques")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 8)
                    StatusPill(
                        pool.available ? "Monté" : "Indisponible",
                        color: pool.available ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme),
                        systemImage: pool.available ? "checkmark.circle.fill" : "xmark.octagon.fill"
                    )
                    .lineLimit(1)
                    .fixedSize()
                }

                HStack(spacing: donutRowSpacing) {
                    ZStack {
                        Chart(slices) { slice in
                            SectorMark(
                                angle: .value("Octets", slice.bytes),
                                innerRadius: .ratio(0.68),
                                angularInset: 2
                            )
                            .foregroundStyle(slice.color)
                            .cornerRadius(4)
                        }
                        .frame(width: donutSize, height: donutSize)

                        VStack(spacing: 1) {
                            Text(String(format: "%.0f %%", pool.usedPct))
                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text("occupé")
                                #if os(tvOS)
                                .font(.caption)
                                #else
                                .font(.caption2)
                                #endif
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: donutSize * 0.62)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        detailMetric(title: "Capacité totale", value: ByteFormatters.formatDecimalTB(pool.totalBytes), color: DesignTokens.primaryText(colorScheme))
                        detailMetric(title: "Espace utilisé", value: ByteFormatters.formatDecimalTB(pool.usedBytes), color: usedColor)
                        detailMetric(title: "Espace libre", value: ByteFormatters.formatDecimalTB(pool.availBytes), color: DesignTokens.nominal(colorScheme))
                    }
                    Spacer()
                }
            }
        }
    }

    private func detailMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                #if os(tvOS)
                .font(.caption)
                #else
                .font(.caption2)
                #endif
                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                .lineLimit(1)
            Text(value)
                #if os(tvOS)
                .font(.system(.headline, design: .monospaced, weight: .semibold))
                #else
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                #endif
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func systemSsdCard(_ ssd: SystemSsdInfo) -> some View {
        let passed = ssd.health.uppercased() == "PASSED"
        return GlassCard(padding: {
            #if os(tvOS)
            20
            #else
            14
            #endif
        }(), cornerRadius: 18) {
            HStack(spacing: 14) {
                Image(systemName: "memorychip.fill")
                    .font(.title2)
                    .foregroundStyle(DesignTokens.accent(accentTheme, colorScheme))
                    .frame(width: {
                        #if os(tvOS)
                        56
                        #else
                        40
                        #endif
                    }(), height: {
                        #if os(tvOS)
                        56
                        #else
                        40
                        #endif
                    }())
                    .background(DesignTokens.surfaceElevated(theme: accentTheme, colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("SSD Système Proxmox")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("\(ssd.model) • \(ssd.devpath) • \(ByteFormatters.formatBytes(ssd.sizeBytes))")
                        #if os(tvOS)
                        .font(.system(.caption, design: .monospaced))
                        #else
                        .font(.system(.caption2, design: .monospaced))
                        #endif
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                StatusPill(
                    ssd.health,
                    color: passed ? DesignTokens.nominal(colorScheme) : DesignTokens.caution(colorScheme),
                    systemImage: passed ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                )
                .lineLimit(1)
                .fixedSize()
            }
        }
    }

    private func drivesSection(_ drives: [PhysicalDriveInfo]) -> some View {
        let q = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = drives.filter { drive in
            let matchesSearch = q.isEmpty
                || drive.label.lowercased().contains(q)
                || drive.model.lowercased().contains(q)
                || drive.devpath.lowercased().contains(q)
                || drive.mount.lowercased().contains(q)
            let matchesSmart = !showHealthyOnly || drive.isHealthy
            return matchesSearch && matchesSmart
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Disques physiques (\(filtered.count))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                Spacer()
                Button {
                    showHealthyOnly.toggle()
                } label: {
                    Label(
                        showHealthyOnly ? "Sains uniquement" : "Tous (SMART)",
                        systemImage: showHealthyOnly ? "checkmark.shield.fill" : "line.3.horizontal.decrease.circle"
                    )
                    #if os(tvOS)
                    .font(.callout.weight(.semibold))
                    #else
                    .font(.caption.weight(.semibold))
                    #endif
                    .lineLimit(1)
                }
                .adaptivePillButtonStyle(
                    tint: showHealthyOnly ? DesignTokens.nominal(colorScheme) : nil,
                    prominent: showHealthyOnly
                )
                .adaptiveSmallControlSize()
                .fixedSize()
            }

            LazyVGrid(columns: adaptiveColumns, spacing: gridSpacing) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, drive in
                    #if os(tvOS)
                    let smartText = drive.health
                    let cardPadding: CGFloat = 20
                    #else
                    let smartText = "SMART \(drive.health)"
                    let cardPadding: CGFloat = 14
                    #endif
                    GlassCard(padding: cardPadding, cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(String(format: "BAY %02d", idx + 1))
                                            #if os(tvOS)
                                            .font(.system(.caption, design: .monospaced, weight: .bold))
                                            #else
                                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                                            #endif
                                            .foregroundStyle(DesignTokens.accent(accentTheme, colorScheme))
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                        Text(drive.label)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.82)
                                    }
                                    Text("\(drive.model) • \(drive.type) (\(drive.rpm))")
                                        #if os(tvOS)
                                        .font(.caption)
                                        #else
                                        .font(.caption2)
                                        #endif
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                }
                                Spacer(minLength: 8)
                                StatusPill(
                                    smartText,
                                    color: drive.isHealthy ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme),
                                    systemImage: drive.isHealthy ? "checkmark.circle.fill" : "exclamationmark.octagon.fill"
                                )
                                .lineLimit(1)
                                .fixedSize()
                            }

                            UsageProgressBar(percentage: drive.usedPct)

                            HStack(spacing: 8) {
                                Text("\(ByteFormatters.formatDecimalTB(drive.usedBytes)) / \(ByteFormatters.formatDecimalTB(drive.totalBytes))")
                                    #if os(tvOS)
                                    .font(.system(.callout, design: .monospaced, weight: .medium))
                                    #else
                                    .font(.system(.caption, design: .monospaced, weight: .medium))
                                    #endif
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                Spacer(minLength: 8)
                                Text("\(drive.devpath) • \(drive.mount)")
                                    #if os(tvOS)
                                    .font(.system(.caption, design: .monospaced))
                                    #else
                                    .font(.system(.caption2, design: .monospaced))
                                    #endif
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                            }
                        }
                    }
                }
            }
        }
    }

    private func proxmoxDatastoresSection(_ storages: [StorageInfo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Datastores Proxmox VE")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText(colorScheme))

            LazyVGrid(columns: adaptiveColumns, spacing: gridSpacing) {
                ForEach(storages) { storage in
                    GlassCard(padding: {
                        #if os(tvOS)
                        20
                        #else
                        14
                        #endif
                    }(), cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Label(storage.name, systemImage: "internaldrive.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Text(storage.type)
                                    #if os(tvOS)
                                    .font(.system(.caption, design: .monospaced))
                                    #else
                                    .font(.system(.caption2, design: .monospaced))
                                    #endif
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(String(format: "%.1f %%", storage.usedPct))
                                    #if os(tvOS)
                                    .font(.system(.callout, design: .monospaced, weight: .bold))
                                    #else
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    #endif
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .lineLimit(1)
                            }
                            UsageProgressBar(percentage: storage.usedPct, tint: DesignTokens.accent(accentTheme, colorScheme))
                            HStack(spacing: 8) {
                                Text("\(ByteFormatters.formatBytes(storage.usedBytes)) utilisés")
                                    #if os(tvOS)
                                    .font(.caption)
                                    #else
                                    .font(.caption2)
                                    #endif
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 8)
                                Text("Total \(ByteFormatters.formatBytes(storage.totalBytes))")
                                    #if os(tvOS)
                                    .font(.caption)
                                    #else
                                    .font(.caption2)
                                    #endif
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                    }
                }
            }
        }
    }
}
