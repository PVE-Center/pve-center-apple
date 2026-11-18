import SwiftUI

private enum ResourceFilter: String, CaseIterable, Identifiable {
    case all = "Tous"
    case running = "Actifs"
    case lxc = "LXC"
    case qemu = "VMs"

    var id: String { rawValue }
}

private struct PendingPowerCommand: Identifiable {
    let id = UUID()
    let resource: PveResource
    let action: PveAction
}

public struct ProxmoxTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme
    @State private var filter: ResourceFilter = .all
    @State private var pendingCommand: PendingPowerCommand?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var displayedResources: [PveResource] {
        viewModel.filteredResources.filter { item in
            switch filter {
            case .all: return true
            case .running: return item.isRunning
            case .lxc: return item.type == .lxc
            case .qemu: return item.type == .qemu
            }
        }
    }

    private var adaptiveColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 740), spacing: 24)]
        #elseif os(macOS)
        return [GridItem(.adaptive(minimum: 340), spacing: 14)]
        #else
        return [GridItem(.flexible())]
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return 14
        #endif
    }

    private var actionSpacing: CGFloat {
        #if os(tvOS)
        return 12
        #else
        return 8
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let node = viewModel.pveOverview?.node {
                    nodeOverviewCard(node)
                }

                HStack(spacing: 12) {
                    Text("Conteneurs & VMs (\(displayedResources.count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .lineLimit(1)
                    Spacer()
                    AdaptiveSegmentedControl(
                        options: ResourceFilter.allCases,
                        selection: $filter,
                        title: \.rawValue
                    )
                }

                LazyVGrid(columns: adaptiveColumns, spacing: gridSpacing) {
                    ForEach(displayedResources) { resource in
                        resourceCard(resource)
                    }
                }

                if displayedResources.isEmpty {
                    GlassCard {
                        ContentUnavailableView(
                            "Aucune ressource",
                            systemImage: "server.rack",
                            description: Text("Aucun conteneur LXC ou VM ne correspond à votre filtre.")
                        )
                    }
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
        .sensoryFeedback(.selection, trigger: filter)
        #endif
        .confirmationDialog(
            pendingCommand.map { "\($0.action.label) \($0.resource.name) (#\($0.resource.vmid)) ?" } ?? "",
            isPresented: Binding(
                get: { pendingCommand != nil },
                set: { if !$0 { pendingCommand = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let cmd = pendingCommand {
                Button(
                    cmd.action.label,
                    role: cmd.action.isDestructive ? .destructive : nil
                ) {
                    Task {
                        await viewModel.executePveAction(resource: cmd.resource, action: cmd.action)
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
        } message: {
            if let cmd = pendingCommand {
                Text(cmd.action.warningMessage)
            }
        }
    }

    private func nodeOverviewCard(_ node: NodeSummary) -> some View {
        let teal = DesignTokens.accent(accentTheme, colorScheme)

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Text("PVE \(node.pveVersion) • Uptime \(node.uptimeHuman)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                    Spacer(minLength: 8)
                    StatusPill("CPU \(Int(node.cpuPct)) %", color: teal, systemImage: "cpu")
                        .lineLimit(1)
                        .fixedSize()
                }

                VStack(spacing: 10) {
                    metricRow(
                        label: "Processeur",
                        value: String(format: "%.1f %% (%d vCPU)", node.cpuPct, node.cpuThreads),
                        pct: node.cpuPct,
                        tint: teal
                    )
                    metricRow(
                        label: "Mémoire RAM",
                        value: "\(ByteFormatters.formatBytes(node.memUsedBytes)) / \(ByteFormatters.formatBytes(node.memTotalBytes))",
                        pct: node.memPct,
                        tint: DesignTokens.secondaryText(colorScheme)
                    )
                    let rootPct = node.rootfsTotalBytes > 0
                        ? (Double(node.rootfsUsedBytes) / Double(node.rootfsTotalBytes)) * 100
                        : 0
                    metricRow(
                        label: "Disque RootFS",
                        value: "\(ByteFormatters.formatBytes(node.rootfsUsedBytes)) / \(ByteFormatters.formatBytes(node.rootfsTotalBytes))",
                        pct: rootPct,
                        tint: DesignTokens.nominal(colorScheme)
                    )
                }
            }
        }
    }

    private func metricRow(label: String, value: String, pct: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    .lineLimit(1)
                Spacer()
                Text(value)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            UsageProgressBar(percentage: pct, tint: tint)
        }
    }

    private func resourceCard(_ res: PveResource) -> some View {
        let nominal = DesignTokens.nominal(colorScheme)
        let teal = DesignTokens.accent(accentTheme, colorScheme)
        #if os(tvOS)
        let cardPadding: CGFloat = 20
        let iconBoxSize: CGFloat = 52
        #else
        let cardPadding: CGFloat = 14
        let iconBoxSize: CGFloat = 38
        #endif

        let card = GlassCard(padding: cardPadding, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: res.type.symbolName)
                        .font(.title3)
                        .foregroundStyle(res.isRunning ? teal : DesignTokens.secondaryText(colorScheme))
                        .frame(width: iconBoxSize, height: iconBoxSize)
                        .background(
                            DesignTokens.surfaceElevated(theme: accentTheme, colorScheme),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(res.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text("#\(res.vmid)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        HStack(spacing: 6) {
                            Text(res.type.badgeLabel)
                                #if os(tvOS)
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                #else
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                #endif
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            Text("•")
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            Text(res.isRunning ? "Uptime \(res.uptimeHuman)" : "Arrêté")
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

                    Spacer(minLength: 8)

                    StatusPill(
                        res.isRunning ? "Actif" : "Stop",
                        color: res.isRunning ? nominal : DesignTokens.secondaryText(colorScheme),
                        systemImage: res.isRunning ? "checkmark.circle.fill" : "pause.circle.fill"
                    )
                    .lineLimit(1)
                    .fixedSize()
                }

                if res.isRunning {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CPU \(String(format: "%.1f %%", res.cpuPct))")
                                #if os(tvOS)
                                .font(.system(.caption, design: .monospaced))
                                #else
                                .font(.system(.caption2, design: .monospaced))
                                #endif
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            UsageProgressBar(percentage: res.cpuPct, tint: teal)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RAM \(ByteFormatters.formatBytes(res.memUsedBytes)) / \(ByteFormatters.formatBytes(res.memTotalBytes)) (\(Int(res.memPct)) %)")
                                #if os(tvOS)
                                .font(.system(.caption, design: .monospaced))
                                #else
                                .font(.system(.caption2, design: .monospaced))
                                #endif
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            UsageProgressBar(percentage: res.memPct, tint: DesignTokens.secondaryText(colorScheme))
                        }
                    }
                }

                actionBar(for: res)
            }
        }

        #if os(tvOS)
        return card
        #else
        return card.contextMenu {
            if !res.isRunning {
                Button {
                    pendingCommand = PendingPowerCommand(resource: res, action: .start)
                } label: {
                    Label("Démarrer", systemImage: "play.fill")
                }
            } else if !res.isSelf {
                Button {
                    pendingCommand = PendingPowerCommand(resource: res, action: .reboot)
                } label: {
                    Label("Redémarrer", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    pendingCommand = PendingPowerCommand(resource: res, action: .shutdown)
                } label: {
                    Label("Éteindre proprement", systemImage: "power")
                }
                Button(role: .destructive) {
                    pendingCommand = PendingPowerCommand(resource: res, action: .stop)
                } label: {
                    Label("Forcer l'arrêt", systemImage: "stop.fill")
                }
            }
        }
        #endif
    }

    private func actionBar(for res: PveResource) -> some View {
        HStack(spacing: actionSpacing) {
            if !res.isRunning {
                powerButton(resource: res, action: .start, prominent: true)
            } else if !res.isSelf {
                powerButton(resource: res, action: .reboot)
                powerButton(
                    resource: res,
                    action: .shutdown,
                    foreground: DesignTokens.caution(colorScheme)
                )
                powerButton(
                    resource: res,
                    action: .stop,
                    foreground: DesignTokens.critical(colorScheme),
                    role: .destructive
                )
            } else {
                Label("Protégé contre l'auto-extinction", systemImage: "shield.checkmark.fill")
                    #if os(tvOS)
                    .font(.caption)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func powerButton(
        resource: PveResource,
        action: PveAction,
        foreground: Color? = nil,
        prominent: Bool = false,
        role: ButtonRole? = nil
    ) -> some View {
        let resolvedTint = foreground ?? (prominent ? DesignTokens.accent(accentTheme, colorScheme) : nil)
        Button(role: role) {
            pendingCommand = PendingPowerCommand(resource: resource, action: action)
        } label: {
            powerButtonLabel(action)
        }
        .adaptiveSmallControlSize()
        .adaptivePillButtonStyle(tint: resolvedTint, prominent: prominent)
    }

    private func powerButtonLabel(_ action: PveAction) -> some View {
        Label(action.shortLabel, systemImage: action.systemImage)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            #if os(tvOS)
            .font(.callout.weight(.semibold))
            #else
            .font(.caption.weight(.semibold))
            #endif
    }
}
