import SwiftUI

public struct ContentView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var onboardingPresentedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.needsOnboarding },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissOnboarding()
                }
            }
        )
    }

    private func handleOnboardingDismiss() {
        if viewModel.serverBaseURL.isEmpty && !viewModel.isDemoMode {
            Task { await viewModel.configureConnection(baseURL: "", demoMode: true) }
        }
    }

    private func handleBannerAcknowledge(_ banner: InAppAlertBanner) {
        let matchingIncident = viewModel.incidents.first {
            $0.id == banner.id || ($0.isActive && banner.serviceId != nil && $0.serviceId == banner.serviceId)
        }
        let targetID = matchingIncident?.id ?? (banner.id.hasPrefix("alert-") ? nil : banner.id)
        viewModel.dismissAlertBanner(id: banner.id)
        if let targetID {
            Task { await viewModel.acknowledgeIncident(id: targetID) }
        }
    }

    private func handleBannerMute(_ banner: InAppAlertBanner) {
        viewModel.dismissAlertBanner(id: banner.id)
        if let serviceId = banner.serviceId {
            Task { await viewModel.muteServiceAlerts(serviceId: serviceId, minutes: 60) }
        }
    }

    public var body: some View {
        ZStack {
            AmbientBackgroundView()

            #if os(macOS)
            macOSBody
            #elseif os(tvOS)
            tvOSBody
            #else
            adaptiveAppleBody
            #endif

            if let liveBanner = viewModel.activeTVBanner {
                VStack {
                    LiveAlertOverlayBanner(
                        banner: liveBanner,
                        onAcknowledge: liveBanner.isResolved ? nil : {
                            handleBannerAcknowledge(liveBanner)
                        },
                        onMuteOneHour: (liveBanner.isResolved || liveBanner.serviceId == nil) ? nil : {
                            handleBannerMute(liveBanner)
                        },
                        onOpenDetails: {
                            viewModel.selectedTab = .operations
                            viewModel.dismissAlertBanner(id: liveBanner.id)
                        },
                        onDismiss: {
                            viewModel.dismissAlertBanner(id: liveBanner.id)
                        }
                    )
                    .padding(.top, liveBannerTopPadding)
                    .padding(.horizontal, DesignTokens.pageHorizontalPadding)
                    Spacer(minLength: 0)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }

            if let toast = viewModel.toast {
                VStack {
                    Spacer(minLength: 0)
                    ToastOverlayView(toast: toast)
                        .padding(.bottom, toastBottomPadding)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(15)
            }
        }
        #if os(tvOS)
        .preferredColorScheme(.dark)
        #else
        .preferredColorScheme(viewModel.preferredColorScheme)
        #endif
        .environment(\.accentTheme, viewModel.accentTheme)
        .tint(viewModel.tintColor(for: colorScheme))
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85),
            value: viewModel.toast?.id
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84),
            value: viewModel.activeTVBanner?.id
        )
        #if os(tvOS)
        .fullScreenCover(
            isPresented: $viewModel.showServerSettings,
            onDismiss: {
                if viewModel.pendingOpenSetupWizard {
                    viewModel.pendingOpenSetupWizard = false
                    viewModel.showServerSetupWizard = true
                }
            }
        ) {
            ServerSettingsSheet(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $viewModel.showServerSetupWizard) {
            ServerSetupWizardSheet(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(
            isPresented: onboardingPresentedBinding,
            onDismiss: handleOnboardingDismiss
        ) {
            OnboardingFlowView(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
        }
        #elseif os(macOS)
        .sheet(
            isPresented: $viewModel.showServerSettings,
            onDismiss: {
                if viewModel.pendingOpenSetupWizard {
                    viewModel.pendingOpenSetupWizard = false
                    viewModel.showServerSetupWizard = true
                }
            }
        ) {
            ServerSettingsSheet(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        .sheet(isPresented: $viewModel.showServerSetupWizard) {
            ServerSetupWizardSheet(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        .sheet(
            isPresented: onboardingPresentedBinding,
            onDismiss: handleOnboardingDismiss
        ) {
            OnboardingFlowView(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        #else
        .sheet(
            isPresented: $viewModel.showServerSettings,
            onDismiss: {
                if viewModel.pendingOpenSetupWizard {
                    viewModel.pendingOpenSetupWizard = false
                    viewModel.showServerSetupWizard = true
                }
            }
        ) {
            ServerSettingsSheet(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        .sheet(isPresented: $viewModel.showServerSetupWizard) {
            ServerSetupWizardSheet(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        .fullScreenCover(
            isPresented: onboardingPresentedBinding,
            onDismiss: handleOnboardingDismiss
        ) {
            OnboardingFlowView(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        #endif
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: viewModel.selectedTab)
        .sensoryFeedback(.success, trigger: viewModel.hapticSuccessTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.hapticImpactTrigger)
        .sensoryFeedback(.warning, trigger: viewModel.activeTVBanner?.id) { _, _ in
            viewModel.activeTVBanner?.isResolved == false
        }
        #elseif !os(tvOS)
        .sensoryFeedback(.success, trigger: viewModel.hapticSuccessTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.hapticImpactTrigger)
        #endif
        .task {
            viewModel.start()
        }
    }

    private var liveBannerTopPadding: CGFloat {
        #if os(tvOS)
        return 24
        #elseif os(macOS)
        return 14
        #else
        return 8
        #endif
    }

    private var operationsBadgeCount: Int {
        viewModel.pendingRequestsCount + viewModel.activeIncidentsCount
    }

    private var toastBottomPadding: CGFloat {
        #if os(macOS)
        return 22
        #elseif os(tvOS)
        return 36
        #else
        return 64
        #endif
    }

    // MARK: - macOS 26 Native Liquid Glass Split View

    #if os(macOS)
    private var macOSBody: some View {
        let themeAccent = viewModel.tintColor(for: colorScheme)
        return NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    macSidebarSection(
                        title: "Supervision",
                        tabs: [.overview, .proxmox, .storage, .services],
                        accent: themeAccent
                    )
                    macSidebarSection(
                        title: "Administration",
                        tabs: [.operations, .users],
                        accent: themeAccent
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
            .background(
                ZStack {
                    AmbientBackgroundView()
                    DesignTokens.surface(theme: viewModel.accentTheme, colorScheme)
                        .opacity(colorScheme == .light ? 0.52 : 0.42)
                }
                .ignoresSafeArea()
            )
            .navigationSplitViewColumnWidth(min: 205, ideal: 230, max: 270)
        } detail: {
            NavigationStack {
                ZStack {
                    AmbientBackgroundView()
                    activeTabContent(for: viewModel.selectedTab)
                        .adaptiveSoftTopScrollEdgeEffect()
                }
                .navigationTitle(viewModel.selectedTab.title)
                .searchable(
                    text: $viewModel.searchText,
                    placement: .toolbar,
                    prompt: "Filtrer LXC, VM, disques, services…"
                )
                .toolbar {
                    commonToolbarItems
                }
            }
        }
        .tint(themeAccent)
    }

    private func macSidebarSection(title: String, tabs: [AppTab], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                .padding(.horizontal, 10)
                .padding(.bottom, 2)

            ForEach(tabs) { tab in
                let badge = tab == .operations ? operationsBadgeCount : 0
                macSidebarButton(for: tab, badge: badge, accent: accent)
            }
        }
    }

    private func macSidebarButton(for tab: AppTab, badge: Int, accent: Color) -> some View {
        let selected = viewModel.selectedTab == tab
        return Button {
            viewModel.selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? accent : DesignTokens.secondaryText(colorScheme))
                    .frame(width: 20)

                Text(tab.title)
                    .font(.subheadline.weight(selected ? .semibold : .medium))
                    .foregroundStyle(selected ? DesignTokens.primaryText(colorScheme) : DesignTokens.primaryText(colorScheme).opacity(0.84))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(selected ? accent : DesignTokens.primaryText(colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (selected ? accent : DesignTokens.secondaryText(colorScheme)).opacity(0.20),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selected
                    ? accent.opacity(colorScheme == .light ? 0.16 : 0.22)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? accent.opacity(0.45) : Color.clear,
                        lineWidth: 0.9
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    #endif

    // MARK: - tvOS 27 Native 10-foot Top TabView

    #if os(tvOS)
    private var tvOSBody: some View {
        TabView(selection: $viewModel.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                tvOSTabScreen(for: tab)
            }
        }
        .tint(viewModel.tintColor(for: .dark))
    }

    @ViewBuilder
    private func tvOSTabScreen(for tab: AppTab) -> some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()
                VStack(spacing: 0) {
                    tvOSHeaderBar(for: tab)
                    activeTabContent(for: tab)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tabItem {
            Label(tab.tvTitle, systemImage: tab.systemImage)
        }
        .tag(tab)
    }

    private var tvOSServerButtonTitle: String {
        if viewModel.isDemoMode { return "Mode Démo" }
        if viewModel.serverBaseURL.isEmpty { return "Connecter" }
        return "Serveur : \(truncatedServerName(maxLength: 16))"
    }

    private func tvOSHeaderBar(for tab: AppTab) -> some View {
        let themeAccent = DesignTokens.accent(viewModel.accentTheme, .dark)
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.primaryText(.dark))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Circle()
                        .fill(
                            viewModel.isDemoMode
                                ? themeAccent
                                : (viewModel.connectionError == nil && !viewModel.serverBaseURL.isEmpty ? DesignTokens.nominal(.dark) : DesignTokens.caution(.dark))
                        )
                        .frame(width: 10, height: 10)
                    Text(
                        viewModel.isDemoMode
                            ? "Mode Démo actif"
                            : (viewModel.serverBaseURL.isEmpty ? "Aucun serveur connecté" : viewModel.activeServerName)
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DesignTokens.secondaryText(.dark))
                    .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 14) {
                RealtimeSyncPill(
                    isDemoMode: viewModel.isDemoMode,
                    state: viewModel.realtimeState,
                    activeIncidentsCount: viewModel.activeIncidentsCount
                )

                if !viewModel.isDemoMode && viewModel.serverBaseURL.isEmpty {
                    Button {
                        Task { await viewModel.configureConnection(baseURL: "", demoMode: true) }
                    } label: {
                        Label("Mode Démo", systemImage: "sparkles")
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .adaptivePillButtonStyle(tint: themeAccent, prominent: true)
                }

                Button {
                    viewModel.showServerSettings = true
                } label: {
                    Label(
                        tvOSServerButtonTitle,
                        systemImage: viewModel.isDemoMode ? "sparkles" : "server.rack"
                    )
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .adaptivePillButtonStyle()

                Button {
                    // Guard instead of .disabled so 5s silent auto-refresh never drops tvOS focus.
                    guard !viewModel.isRefreshing else { return }
                    Task { await viewModel.refreshAll(silent: false) }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .opacity(viewModel.isRefreshing ? 0.65 : 1.0)
                }
                .adaptivePillButtonStyle()
                .accessibilityLabel(viewModel.isRefreshing ? "Synchronisation…" : "Actualiser")
            }
        }
        .padding(.horizontal, DesignTokens.pageHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, DesignTokens.pageHorizontalPadding)
        }
        .focusSection()
    }
    #endif

    // MARK: - iOS / iPadOS 27 Native Liquid Glass Layout

    #if !os(macOS) && !os(tvOS)
    @ViewBuilder
    private var adaptiveAppleBody: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                List(selection: Binding(
                    get: { Optional(viewModel.selectedTab) },
                    set: { if let v = $0 { viewModel.selectedTab = v } }
                )) {
                    Section("Supervision") {
                        Label(AppTab.overview.title, systemImage: AppTab.overview.systemImage).tag(AppTab.overview)
                        Label(AppTab.proxmox.title, systemImage: AppTab.proxmox.systemImage).tag(AppTab.proxmox)
                        Label(AppTab.storage.title, systemImage: AppTab.storage.systemImage).tag(AppTab.storage)
                        Label(AppTab.services.title, systemImage: AppTab.services.systemImage).tag(AppTab.services)
                    }
                    Section("Administration") {
                        Label(AppTab.operations.title, systemImage: AppTab.operations.systemImage)
                            .badge(operationsBadgeCount)
                            .tag(AppTab.operations)
                        Label(AppTab.users.title, systemImage: AppTab.users.systemImage).tag(AppTab.users)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background { AmbientBackgroundView() }
                .navigationTitle("PVE Center")
            } detail: {
                NavigationStack {
                    ZStack {
                        AmbientBackgroundView()
                        activeTabContent(for: viewModel.selectedTab)
                            .adaptiveSoftTopScrollEdgeEffect()
                    }
                    .navigationTitle(viewModel.selectedTab.title)
                    .searchable(text: $viewModel.searchText, prompt: "Filtrer LXC, VM, disques, services…")
                    .toolbar {
                        commonToolbarItems
                    }
                }
            }
        } else {
            TabView(selection: compactTabBinding) {
                ForEach(AppTab.compactTabs) { tab in
                    tabScreen(
                        for: tab,
                        badge: tab == .operations ? operationsBadgeCount : 0
                    ) {
                        activeTabContent(for: tab)
                    }
                }
            }
            #if os(iOS)
            .adaptiveTabBarMinimizeOnScroll()
            #endif
            .searchable(text: $viewModel.searchText, prompt: "Filtrer LXC, VM, disques, services…")
        }
    }

    private var compactTabBinding: Binding<AppTab> {
        Binding(
            get: {
                viewModel.selectedTab == .services ? .overview : viewModel.selectedTab
            },
            set: { newValue in
                viewModel.selectedTab = newValue
            }
        )
    }

    @ViewBuilder
    private func tabScreen<Content: View>(
        for tab: AppTab,
        badge: Int = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()
                content()
                    .adaptiveSoftTopScrollEdgeEffect()
            }
            .navigationTitle(tab.title)
            .toolbar {
                commonToolbarItems
            }
        }
        .tabItem {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
        .badge(badge)
    }
    #endif

    // MARK: - Shared Views & Toolbar

    @ViewBuilder
    private func activeTabContent(for tab: AppTab) -> some View {
        switch tab {
        case .overview:
            OverviewTabView(viewModel: viewModel)
        case .proxmox:
            ProxmoxTabView(viewModel: viewModel)
        case .storage:
            StorageTabView(viewModel: viewModel)
        case .services:
            ServicesTabView(viewModel: viewModel)
        case .operations:
            OperationsTabView(viewModel: viewModel)
        case .users:
            UsersTabView(viewModel: viewModel)
        }
    }

    @ToolbarContentBuilder
    private var commonToolbarItems: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button {
                viewModel.selectedTab = .operations
            } label: {
                RealtimeSyncPill(
                    isDemoMode: viewModel.isDemoMode,
                    state: viewModel.realtimeState,
                    activeIncidentsCount: viewModel.activeIncidentsCount
                )
            }
            .buttonStyle(.plain)
            .help("État temps réel (\(viewModel.realtimeState.label)) — Voir l'activité et les incidents")
        }
        #else
        ToolbarItem(placement: .automatic) {
            Button {
                viewModel.selectedTab = .operations
            } label: {
                RealtimeSyncPill(
                    isDemoMode: viewModel.isDemoMode,
                    state: viewModel.realtimeState,
                    activeIncidentsCount: viewModel.activeIncidentsCount
                )
            }
            .buttonStyle(.plain)
            #if !os(tvOS)
            .help("État temps réel (\(viewModel.realtimeState.label)) — Voir l'activité et les incidents")
            #endif
        }
        #endif

        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            Button {
                viewModel.toggleAutoRefresh()
            } label: {
                Label(
                    viewModel.autoRefresh ? "Live 5s" : "En pause",
                    systemImage: viewModel.autoRefresh ? "pause.circle.fill" : "play.circle"
                )
            }
            .help("Activer ou suspendre l'actualisation automatique (⌘L)")
        }
        #endif

        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.showServerSettings = true
            } label: {
                Label(
                    shortServerButtonTitle,
                    systemImage: "server.rack"
                )
            }
            #if !os(tvOS)
            .help("Configurer le serveur Tailscale Serve ou le Mode Démo (⌘;)")
            #endif
        }

        ToolbarItem(placement: .automatic) {
            Button {
                Task { await viewModel.refreshAll(silent: false) }
            } label: {
                #if os(macOS)
                Label(
                    viewModel.isRefreshing ? "Synchronisation…" : "Rafraîchir",
                    systemImage: "arrow.clockwise"
                )
                #else
                Image(systemName: "arrow.clockwise")
                #endif
            }
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel(viewModel.isRefreshing ? "Synchronisation…" : "Rafraîchir")
            #if !os(tvOS)
            .help("Rafraîchir toutes les données maintenant (⌘R)")
            #endif
        }
    }

    private var shortServerButtonTitle: String {
        if viewModel.isDemoMode { return "Démo" }
        if viewModel.serverBaseURL.isEmpty { return "Serveur" }
        return truncatedServerName(maxLength: 14)
    }

    private func truncatedServerName(maxLength: Int) -> String {
        let name = viewModel.activeServerName
        guard name.count > maxLength, maxLength > 1 else { return name }
        return String(name.prefix(maxLength - 1)) + "…"
    }
}
