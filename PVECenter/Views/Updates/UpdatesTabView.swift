import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#elseif os(macOS) && canImport(AppKit)
import AppKit
#endif

private enum UpdateFilterCategory: String, CaseIterable, Identifiable {
    case all
    case pveCenter = "pve_center"
    case proxmox
    case containersVms = "containers_vms"
    case docker

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "Tout"
        case .pveCenter: "PVE Center"
        case .proxmox: "Proxmox VE"
        case .containersVms: "LXC & VMs"
        case .docker: "Docker"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .pveCenter: "sparkles"
        case .proxmox: "server.rack"
        case .containersVms: "shippingbox"
        case .docker: "cube.box"
        }
    }
}

public struct UpdatesTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var selectedCategory: UpdateFilterCategory = .all
    @State private var includePanelSelf: Bool = true
    @State private var autoremove: Bool = true
    @State private var confirmAllPresented: Bool = false
    @State private var showSSHSetupSheet: Bool = false
    @State private var showLogs: Bool = true

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var overview: UpdatesOverviewResponse? {
        viewModel.updatesOverview
    }

    private var targets: [UpdateTargetItem] {
        let all = overview?.targets ?? []
        let catFiltered = selectedCategory == .all
            ? all
            : all.filter { $0.category == selectedCategory.rawValue }
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return catFiltered }
        return catFiltered.filter {
            $0.name.lowercased().contains(query) || $0.subtitle.lowercased().contains(query)
        }
    }

    private var isJobRunning: Bool {
        overview?.activeJob?.status == "running"
    }

    private var executableUpdateCount: Int {
        (overview?.targets ?? []).filter {
            $0.canExecute
                && ($0.id != "panel:server" || includePanelSelf)
                && ($0.updateAvailable || $0.category == "containers_vms" || $0.category == "docker")
        }.count
    }

    public var body: some View {
        let accent = DesignTokens.accent(accentTheme, colorScheme)

        ScrollView {
            LazyVStack(spacing: 16) {
                heroCard(accent: accent)

                if let job = overview?.activeJob {
                    liveJobCard(job, accent: accent)
                }

                filterBar(accent: accent)

                if targets.isEmpty {
                    GlassCard {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(DesignTokens.nominal(colorScheme))
                            Text("Aucune cible trouvée pour ce filtre.")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                } else {
                    ForEach(targets) { target in
                        targetCard(target, accent: accent)
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
            await viewModel.checkUpdates()
        }
        #endif
        .task {
            if overview == nil {
                await viewModel.refreshUpdatesOnly()
            }
        }
        .confirmationDialog(
            "Tout mettre à jour (\(executableUpdateCount) cibles) ?",
            isPresented: $confirmAllPresented,
            titleVisibility: .visible
        ) {
            Button("Lancer toutes les mises à jour") {
                Task {
                    await viewModel.runUpdates(
                        targetIds: ["all"],
                        includePanelSelf: includePanelSelf,
                        autoremove: autoremove
                    )
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les nœuds Proxmox, conteneurs LXC/VMs et piles Docker seront mis à jour séquentiellement. Si pve-panel est inclus, il redémarrera en dernier.")
        }
        .sheet(isPresented: $showSSHSetupSheet) {
            sshSetupSheetView(accent: accent)
        }
    }

    private func heroCard(accent: Color) -> some View {
        GlassCard(elevated: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Centre de Mises à Jour Unifié")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Text("PVE Command Center, Proxmox VE, LXC/VMs et piles Docker Compose.")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                    Spacer(minLength: 8)
                    StatusPill(
                        "\(overview?.summary.updatesAvailable ?? 0) MAJ",
                        color: (overview?.summary.updatesAvailable ?? 0) > 0
                            ? DesignTokens.caution(colorScheme)
                            : DesignTokens.nominal(colorScheme),
                        systemImage: (overview?.summary.updatesAvailable ?? 0) > 0
                            ? "exclamationmark.circle.fill"
                            : "checkmark.circle.fill"
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.checkUpdates() }
                    } label: {
                        Label(
                            viewModel.isCheckingUpdates ? "Analyse…" : "Vérifier",
                            systemImage: "arrow.clockwise"
                        )
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    }
                    .adaptivePillButtonStyle()
                    .disabled(viewModel.isCheckingUpdates || isJobRunning)

                    Button {
                        confirmAllPresented = true
                    } label: {
                        Label(
                            isJobRunning ? "En cours…" : "Tout mettre à jour (\(executableUpdateCount))",
                            systemImage: "sparkles"
                        )
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    }
                    .adaptivePillButtonStyle(tint: accent, prominent: true)
                    .disabled(isJobRunning || viewModel.isStartingUpdateJob || executableUpdateCount == 0)

                    Button {
                        showSSHSetupSheet = true
                        Task { await viewModel.loadUpdatesSetupInfo() }
                    } label: {
                        Label(
                            overview?.sshConfigured == true ? "SSH prêt" : "Clé SSH",
                            systemImage: "key.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    }
                    .adaptivePillButtonStyle(
                        tint: overview?.sshConfigured == true
                            ? DesignTokens.nominal(colorScheme)
                            : DesignTokens.caution(colorScheme)
                    )
                }
            }
        }
    }

    private func filterBar(accent: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(UpdateFilterCategory.allCases) { category in
                    let active = selectedCategory == category
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(category.label, systemImage: category.systemImage)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .adaptivePillButtonStyle(tint: accent, prominent: active)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func liveJobCard(_ job: UpdateJob, accent: Color) -> some View {
        let statusColor: Color = switch job.status {
        case "succeeded": DesignTokens.nominal(colorScheme)
        case "failed": DesignTokens.critical(colorScheme)
        default: accent
        }

        return GlassCard(elevated: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Opération \(job.id) — \(job.progressPct) %", systemImage: "terminal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                    Spacer()
                    StatusPill(job.status == "running" ? "En cours" : (job.status == "succeeded" ? "Terminé" : "Erreur"), color: statusColor)
                }

                ProgressView(value: Double(max(0, min(100, job.progressPct))), total: 100)
                    .tint(statusColor)

                ForEach(job.steps) { step in
                    HStack(spacing: 8) {
                        Image(systemName: step.status == "succeeded" ? "checkmark.circle.fill" : (step.status == "failed" ? "xmark.circle.fill" : "clock.fill"))
                            .font(.caption)
                            .foregroundStyle(step.status == "succeeded" ? DesignTokens.nominal(colorScheme) : (step.status == "failed" ? DesignTokens.critical(colorScheme) : accent))
                        Text(step.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            .lineLimit(1)
                        Spacer()
                        Text(step.message)
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            .lineLimit(1)
                    }
                }

                if !job.logs.isEmpty {
                    Button {
                        showLogs.toggle()
                    } label: {
                        Label(showLogs ? "Masquer les logs" : "Afficher les logs (\(job.logs.count))", systemImage: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .adaptivePillButtonStyle()
                    .adaptiveSmallControlSize()

                    if showLogs {
                        ScrollView {
                            Text(job.logs.joined(separator: "\n"))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                        .padding(10)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func targetCard(_ target: UpdateTargetItem, accent: Color) -> some View {
        let cardContent = VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        .lineLimit(1)
                    Text(target.subtitle)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                StatusPill(
                    target.updateAvailable ? target.latestVersion : "À jour",
                    color: target.updateAvailable ? DesignTokens.caution(colorScheme) : DesignTokens.nominal(colorScheme)
                )
            }

            if !target.packagesPreview.isEmpty {
                Text(target.packagesPreview.prefix(4).joined(separator: " • "))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    .lineLimit(2)
            }

            HStack {
                Text(target.currentVersion)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                Spacer()
                #if !os(tvOS)
                if target.canExecute {
                    Button {
                        Task {
                            await viewModel.runUpdates(
                                targetIds: [target.id],
                                includePanelSelf: true,
                                autoremove: autoremove
                            )
                        }
                    } label: {
                        Label("Mettre à jour", systemImage: "arrow.up.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .adaptivePillButtonStyle(tint: accent, prominent: target.updateAvailable)
                    .adaptiveSmallControlSize()
                    .disabled(isJobRunning || viewModel.isStartingUpdateJob)
                } else if let urlStr = target.releaseUrl, let url = URL(string: urlStr) {
                    Link(destination: url) {
                        Label("Releases", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                    }
                    .adaptivePillButtonStyle()
                    .adaptiveSmallControlSize()
                }
                #else
                if target.canExecute {
                    StatusPill("Sélectionner pour MAJ", color: accent)
                }
                #endif
            }
        }

        #if os(tvOS)
        if target.canExecute {
            Button {
                Task {
                    await viewModel.runUpdates(
                        targetIds: [target.id],
                        includePanelSelf: true,
                        autoremove: autoremove
                    )
                }
            } label: {
                cardContent.padding(18)
            }
            .buttonStyle(TVGlassCardButtonStyle(cornerRadius: 20))
            .disabled(isJobRunning || viewModel.isStartingUpdateJob)
        } else {
            GlassCard { cardContent }
        }
        #else
        GlassCard { cardContent }
        #endif
    }

    private func sshSetupSheetView(accent: Color) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.isLoadingUpdatesSetup {
                        ProgressView("Vérification SSH Proxmox…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else if let info = viewModel.updatesSetupInfo {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                StatusPill(
                                    info.sshConfigured ? "SSH Proxmox connecté" : "Autorisation requise",
                                    color: info.sshConfigured ? DesignTokens.nominal(colorScheme) : DesignTokens.caution(colorScheme)
                                )
                                Text(info.sshMessage)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Commande Proxmox VE (shell root)")
                                    .font(.caption.weight(.semibold))
                                Text(info.proxmoxOneLiner)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .textSelectionIfAvailable()
                                #if !os(tvOS)
                                Button {
                                    copyToPasteboard(info.proxmoxOneLiner)
                                    viewModel.showToast("Commande copiée.", isError: false)
                                } label: {
                                    Label("Copier la commande", systemImage: "doc.on.doc")
                                }
                                .adaptivePillButtonStyle(tint: accent, prominent: true)
                                .adaptiveSmallControlSize()
                                #endif
                            }
                        }

                        HStack {
                            Button {
                                Task { await viewModel.rotateUpdatesSSHKey() }
                            } label: {
                                Label("Régénérer la clé", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .adaptivePillButtonStyle(tint: DesignTokens.critical(colorScheme))

                            Spacer()

                            Button {
                                Task {
                                    await viewModel.loadUpdatesSetupInfo()
                                    await viewModel.refreshUpdatesOnly()
                                }
                            } label: {
                                Label("Retester", systemImage: "checkmark.shield")
                            }
                            .adaptivePillButtonStyle(tint: accent, prominent: true)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Clé SSH Proxmox")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { showSSHSetupSheet = false }
                }
            }
        }
    }

    #if !os(tvOS)
    private func copyToPasteboard(_ value: String) {
        #if os(iOS) && canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif os(macOS) && canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
    #endif
}

private extension View {
    @ViewBuilder
    func textSelectionIfAvailable() -> some View {
        #if os(tvOS)
        self
        #else
        self.textSelection(.enabled)
        #endif
    }
}
