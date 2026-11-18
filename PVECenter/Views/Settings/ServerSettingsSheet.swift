import SwiftUI

private enum SettingsModalRoute: String, Identifiable {
    case setupWizard
    case onboarding
    case yamlEditor
    case notifications
    case appleTVPairing
    case qrScanner

    var id: String { rawValue }
}

private enum SettingsSidebarTab: String, CaseIterable, Identifiable {
    case appearance
    case servers
    case proxmox
    case alertsAndTV
    case yamlAndSync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Apparence & Verre"
        case .servers: "Serveurs & Tailscale"
        case .proxmox: "Proxmox & Médias"
        case .alertsAndTV: "Alertes & Apple TV"
        case .yamlAndSync: "YAML, Sync & Démo"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: "Couleurs Cider & Aperçu"
        case .servers: "Hôtes, Bonjour & QR"
        case .proxmox: "Intégrations & Services"
        case .alertsAndTV: "APNs, Webhooks & PIN"
        case .yamlAndSync: "Config YAML & Mode Démo"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintpalette.fill"
        case .servers: "server.rack"
        case .proxmox: "slider.horizontal.3"
        case .alertsAndTV: "bell.badge.fill"
        case .yamlAndSync: "sparkles"
        }
    }

    var badgeColors: [Color] {
        switch self {
        case .appearance: [Color(red: 0.98, green: 0.14, blue: 0.23), .pink]
        case .servers: [.cyan, .blue]
        case .proxmox: [.indigo, .purple]
        case .alertsAndTV: [.orange, .red]
        case .yamlAndSync: [.mint, .teal]
        }
    }
}

public struct ServerSettingsSheet: View {
    public var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedSidebarTab: SettingsSidebarTab = .appearance
    @State private var sidebarSearch: String = ""
    @State private var serverNameInput: String = ""
    @State private var urlInput: String
    @State private var tokenInput: String = ""
    @State private var activeTokenEdit: String = ""
    @State private var deepLinkInput: String = ""
    @State private var testing: Bool = false
    @State private var statusBanner: (isError: Bool, text: String)?
    @State private var activeModal: SettingsModalRoute?

    #if os(tvOS)
    @FocusState private var isDemoButtonFocused: Bool
    #endif

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _urlInput = State(initialValue: viewModel.serverBaseURL)
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { viewModel.appearanceMode },
            set: { viewModel.setAppearanceMode($0) }
        )
    }

    private var accentBinding: Binding<AccentTheme> {
        Binding(
            get: { viewModel.accentTheme },
            set: { viewModel.setAccentTheme($0) }
        )
    }

    private var isSplitStudioLayout: Bool {
        #if os(macOS)
        return true
        #elseif os(iOS)
        return horizontalSizeClass == .regular
        #else
        return false
        #endif
    }

    public var body: some View {
        Group {
            #if os(tvOS)
            tvOSBody
                .fullScreenCover(item: $activeModal) { route in
                    modalView(for: route)
                        .environment(\.accentTheme, viewModel.accentTheme)
                        .tint(viewModel.tintColor(for: .dark))
                        .preferredColorScheme(.dark)
                }
            #else
            standardBody
                .sheet(item: $activeModal) { route in
                    modalView(for: route)
                        .environment(\.accentTheme, viewModel.accentTheme)
                        .tint(viewModel.tintColor(for: colorScheme))
                        .preferredColorScheme(viewModel.preferredColorScheme)
                }
            #endif
        }
        .environment(\.accentTheme, viewModel.accentTheme)
        #if os(tvOS)
        .tint(viewModel.tintColor(for: .dark))
        .preferredColorScheme(.dark)
        #else
        .tint(viewModel.tintColor(for: colorScheme))
        .preferredColorScheme(viewModel.preferredColorScheme)
        #endif
        .onAppear {
            viewModel.discoveryService.startPVEDiscovery()
            #if os(tvOS)
            isDemoButtonFocused = true
            #endif
        }
    }

    @ViewBuilder
    private func modalView(for route: SettingsModalRoute) -> some View {
        switch route {
        case .setupWizard:
            ServerSetupWizardSheet(viewModel: viewModel)
        case .onboarding:
            OnboardingFlowView(viewModel: viewModel)
        case .yamlEditor:
            YAMLConfigEditorView(viewModel: viewModel)
        case .notifications:
            NotificationsSettingsView(viewModel: viewModel)
        case .appleTVPairing:
            AppleTVPairingView(viewModel: viewModel)
        case .qrScanner:
            QRScannerView { scanned in
                serverURLInputApply(scanned)
            }
        }
    }

    // MARK: - tvOS 10-Foot Body

    #if os(tvOS)
    private var tvOSBody: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Paramètres & Connexion")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            Text("Serveurs, apparence, notifications, YAML et appairage Apple TV.")
                                .font(.callout)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Label("Fermer", systemImage: "xmark.circle.fill")
                                .font(.callout.weight(.semibold))
                        }
                        .adaptivePillButtonStyle()
                    }

                    HStack(alignment: .top, spacing: 32) {
                        VStack(spacing: 24) {
                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 16) {
                                    Label("Apparence & Couleur Studio", systemImage: "paintpalette.fill")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: 220), spacing: 14)],
                                        spacing: 14
                                    ) {
                                        ForEach(AccentTheme.allCases) { preset in
                                            let selected = viewModel.accentTheme == preset
                                            let presetAccent = DesignTokens.accent(preset, colorScheme)
                                            Button {
                                                viewModel.setAccentTheme(preset)
                                            } label: {
                                                HStack(spacing: 10) {
                                                    Circle()
                                                        .fill(
                                                            LinearGradient(
                                                                colors: [
                                                                    presetAccent,
                                                                    DesignTokens.secondaryAccent(preset, colorScheme),
                                                                ],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            )
                                                        )
                                                        .frame(width: 22, height: 22)
                                                    Text(preset.title)
                                                        .font(.callout.weight(.semibold))
                                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                                        .lineLimit(1)
                                                    Spacer(minLength: 4)
                                                    if selected {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundStyle(presetAccent)
                                                    }
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 12)
                                                .frame(maxWidth: .infinity, minHeight: 54)
                                            }
                                            .adaptiveIconTileButtonStyle(
                                                isSelected: selected,
                                                accent: presetAccent,
                                                cornerRadius: 14
                                            )
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Label("Outils & Configuration avancée", systemImage: "wrench.and.screwdriver.fill")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    quickLinkButton(
                                        title: "Appairage Apple TV (PIN 6 chiffres)",
                                        systemImage: "appletv.fill",
                                        route: .appleTVPairing
                                    )
                                    quickLinkButton(
                                        title: "Notifications & Webhooks",
                                        systemImage: "bell.badge.fill",
                                        route: .notifications
                                    )
                                    quickLinkButton(
                                        title: "Configuration YAML (lecture)",
                                        systemImage: "doc.text.fill",
                                        route: .yamlEditor
                                    )
                                    quickLinkButton(
                                        title: "Relancer l'assistant d'installation",
                                        systemImage: "wand.and.stars",
                                        route: .onboarding
                                    )
                                }
                            }

                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Label("Mode Démo interactif", systemImage: "sparkles")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.indigo)
                                    Text("Explorez toutes les vues SwiftUI, graphiques Swift Charts et la supervision Proxmox hors-ligne sans serveur.")
                                        .font(.callout)
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))

                                    Button {
                                        Task {
                                            await viewModel.configureConnection(baseURL: urlInput, demoMode: true)
                                            dismiss()
                                        }
                                    } label: {
                                        Label(
                                            viewModel.isDemoMode ? "Mode Démo déjà actif" : "Activer le Mode Démo",
                                            systemImage: "play.fill"
                                        )
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                    }
                                    .adaptivePillButtonStyle(tint: .indigo, prominent: true, cornerRadius: 16)
                                    .focused($isDemoButtonFocused)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 24) {
                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Serveurs enregistrés (\(viewModel.savedServers.count))")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    if viewModel.savedServers.isEmpty {
                                        Text("Aucun serveur enregistré pour le moment.")
                                            .font(.callout)
                                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                    } else {
                                        ForEach(viewModel.savedServers) { server in
                                            let isActive = !viewModel.isDemoMode
                                                && server.baseURL.caseInsensitiveCompare(viewModel.serverBaseURL) == .orderedSame
                                            HStack(spacing: 12) {
                                                Button {
                                                    Task {
                                                        await viewModel.setActiveServer(server)
                                                        dismiss()
                                                    }
                                                } label: {
                                                    HStack(spacing: 12) {
                                                        Image(systemName: isActive ? "checkmark.circle.fill" : "server.rack")
                                                            .foregroundStyle(isActive ? .green : DesignTokens.accent(viewModel.accentTheme, colorScheme))
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(server.name)
                                                                .font(.headline)
                                                                .lineLimit(1)
                                                            Text(server.baseURL)
                                                                .font(.caption)
                                                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                                                .lineLimit(1)
                                                                .truncationMode(.middle)
                                                        }
                                                        Spacer()
                                                    }
                                                }
                                                .adaptivePillButtonStyle(
                                                    tint: isActive ? .green : DesignTokens.accent(viewModel.accentTheme, colorScheme),
                                                    cornerRadius: 16
                                                )

                                                Button(role: .destructive) {
                                                    viewModel.removeServer(id: server.id)
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .adaptivePillButtonStyle(
                                                    tint: DesignTokens.critical(colorScheme),
                                                    cornerRadius: 16
                                                )
                                                .accessibilityLabel("Supprimer \(server.name)")
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Ajouter ou connecter un serveur")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    TextField("Nom du serveur", text: $serverNameInput)
                                        .autocorrectionDisabled()
                                    TextField("https://pve-panel.votre-tailnet.ts.net ou IP locale", text: $urlInput)
                                        .autocorrectionDisabled()
                                    SecureField("Jeton Bearer (optionnel)", text: $tokenInput)

                                    let connectDisabled = testing || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    Button {
                                        guard !connectDisabled else { return }
                                        Task { await verifyAndAddServer() }
                                    } label: {
                                        HStack {
                                            Label("Tester et connecter", systemImage: "checkmark.shield.fill")
                                                .font(.callout.weight(.semibold))
                                            Spacer()
                                            if testing { ProgressView() }
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .opacity(connectDisabled ? 0.5 : 1.0)
                                    }
                                    .adaptivePillButtonStyle(
                                        tint: DesignTokens.accent(viewModel.accentTheme, colorScheme),
                                        prominent: true,
                                        cornerRadius: 16
                                    )

                                    if let statusBanner {
                                        Label(
                                            statusBanner.text,
                                            systemImage: statusBanner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                                        )
                                        .font(.callout)
                                        .foregroundStyle(statusBanner.isError ? .red : .green)
                                    }
                                }
                            }

                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Proxmox, Tailscale & Actualisation")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    let wizardUnavailable = viewModel.serverBaseURL.isEmpty && !viewModel.isDemoMode
                                    Button {
                                        guard !wizardUnavailable else { return }
                                        activeModal = .setupWizard
                                    } label: {
                                        HStack {
                                            Label("Configurer Proxmox, Tailscale & Médias…", systemImage: "slider.horizontal.3")
                                                .font(.callout.weight(.semibold))
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .opacity(wizardUnavailable ? 0.45 : 1.0)
                                    }
                                    .adaptivePillButtonStyle(cornerRadius: 16)

                                    Toggle(
                                        "Actualisation automatique (5s)",
                                        isOn: Binding(
                                            get: { viewModel.autoRefresh },
                                            set: { _ in viewModel.toggleAutoRefresh() }
                                        )
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 36)
            }
        }
    }

    private func quickLinkButton(title: String, systemImage: String, route: SettingsModalRoute) -> some View {
        Button {
            activeModal = route
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .adaptivePillButtonStyle(cornerRadius: 16)
    }
    #endif

    // MARK: - iOS & macOS Studio Body (Cider-style Sidebar on macOS/iPadOS)

    private var visibleSidebarTabs: [SettingsSidebarTab] {
        let q = sidebarSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return SettingsSidebarTab.allCases }
        return SettingsSidebarTab.allCases.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    private var standardBody: some View {
        Group {
            if isSplitStudioLayout {
                ciderSplitStudioBody
            } else {
                compactFormBody
            }
        }
        #if os(macOS)
        .frame(minWidth: 740, idealWidth: 820, minHeight: 580, idealHeight: 650)
        #endif
    }

    private var ciderSplitStudioBody: some View {
        let accent = DesignTokens.accent(viewModel.accentTheme, colorScheme)
        let secondaryAccent = DesignTokens.secondaryAccent(viewModel.accentTheme, colorScheme)

        return HStack(spacing: 0) {
            // Sidebar translucide style Cider / macOS
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [accent, secondaryAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        Image(systemName: "gearshape.2.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Préférences")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Text(viewModel.isDemoMode ? "Mode Démo" : "Studio PVE Center")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                }
                .padding(.horizontal, 4)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    TextField("Filtrer…", text: $sidebarSearch)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    DesignTokens.surfaceElevated(theme: viewModel.accentTheme, colorScheme),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(visibleSidebarTabs) { tab in
                            let selected = selectedSidebarTab == tab
                            Button {
                                selectedSidebarTab = tab
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: tab.badgeColors,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 28, height: 28)
                                        Image(systemName: tab.systemImage)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tab.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                            .lineLimit(1)
                                        Text(tab.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    selected
                                        ? accent.opacity(colorScheme == .light ? 0.14 : 0.22)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            selected ? accent.opacity(0.45) : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.isDemoMode ? Color.indigo : (viewModel.serverBaseURL.isEmpty ? Color.orange : Color.green))
                        .frame(width: 8, height: 8)
                    Text(
                        viewModel.isDemoMode
                            ? "Session Démo"
                            : (viewModel.serverBaseURL.isEmpty ? "Hors connexion" : "Connecté au panel")
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    DesignTokens.surfaceElevated(theme: viewModel.accentTheme, colorScheme),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .padding(14)
            .frame(width: 242)
            .background(
                DesignTokens.surface(theme: viewModel.accentTheme, colorScheme)
                    .opacity(colorScheme == .light ? 0.94 : 0.88)
            )

            Divider()

            NavigationStack {
                Form {
                    switch selectedSidebarTab {
                    case .appearance:
                        appearanceSection
                    case .servers:
                        if !viewModel.savedServers.isEmpty {
                            savedServersSection
                        }
                        if !viewModel.discoveryService.pveServers.isEmpty {
                            bonjourDiscoverySection
                        }
                        addServerSection
                        deepLinkPairingSection
                    case .proxmox:
                        proxmoxTailscaleQuickSection
                    case .alertsAndTV:
                        alertsAndTVSection
                    case .yamlAndSync:
                        yamlAndOnboardingSection
                        refreshOptionsSection
                        demoModeSection
                    }
                }
                .formStyle(.grouped)
                #if !os(tvOS)
                .scrollContentBackground(.hidden)
                .background { AmbientBackgroundView() }
                #endif
                .navigationTitle(selectedSidebarTab.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var compactFormBody: some View {
        NavigationStack {
            Form {
                appearanceSection
                quickLinksSection

                if !viewModel.savedServers.isEmpty {
                    savedServersSection
                }

                if !viewModel.discoveryService.pveServers.isEmpty {
                    bonjourDiscoverySection
                }

                addServerSection
                deepLinkPairingSection
                proxmoxTailscaleQuickSection
                demoModeSection
                refreshOptionsSection
            }
            .formStyle(.grouped)
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            .background { AmbientBackgroundView() }
            #endif
            .navigationTitle("Réglages Studio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        let accent = DesignTokens.accent(viewModel.accentTheme, colorScheme)
        let secondaryAccent = DesignTokens.secondaryAccent(viewModel.accentTheme, colorScheme)

        return Group {
            Section("Aperçu en direct") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Style \(viewModel.accentTheme.title)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Text("Icônes dédiées & halo adaptatif")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ServiceIconView(icon: "jellyfin", isOnline: true, size: 32)
                        ServiceIconView(icon: "zoraxy", isOnline: true, size: 32)
                        ServiceIconView(icon: "nextcloud", isOnline: true, size: 32)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(
                    LinearGradient(
                        colors: [accent.opacity(0.16), secondaryAccent.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            Section("Apparence & Couleur d'accentuation") {
                Picker("Thème", selection: appearanceBinding) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                    ForEach(AccentTheme.allCases) { preset in
                        let selected = viewModel.accentTheme == preset
                        let c1 = DesignTokens.accent(preset, colorScheme)
                        let c2 = DesignTokens.secondaryAccent(preset, colorScheme)

                        Button {
                            viewModel.setAccentTheme(preset)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 20, height: 20)
                                    .overlay {
                                        if selected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                Text(preset.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                selected ? c1.opacity(0.16) : DesignTokens.surfaceElevated(theme: viewModel.accentTheme, colorScheme),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(selected ? c1 : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var alertsAndTVSection: some View {
        Section("Alertes Push & Appareils Apple") {
            Button {
                activeModal = .notifications
            } label: {
                quickLinkRow(
                    title: "Notifications & Alertes (APNs / Webhooks)",
                    subtitle: "Permissions Apple, APNs serveur, Discord, Telegram, ntfy",
                    systemImage: "bell.badge.fill",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)

            Button {
                activeModal = .appleTVPairing
            } label: {
                quickLinkRow(
                    title: "Appairage Apple TV (PIN 6 chiffres)",
                    subtitle: "Transfert chiffré CryptoKit P-256 + AES-GCM",
                    systemImage: "appletv.fill",
                    tint: DesignTokens.accent(viewModel.accentTheme, colorScheme)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var yamlAndOnboardingSection: some View {
        Section("Configuration déclarative & Onboarding") {
            Button {
                activeModal = .yamlEditor
            } label: {
                quickLinkRow(
                    title: "Éditeur YAML & Rechargement à chaud",
                    subtitle: "Consulter, valider, modifier et exporter config.yaml",
                    systemImage: "doc.text.magnifyingglass",
                    tint: DesignTokens.accent(viewModel.accentTheme, colorScheme)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.serverBaseURL.isEmpty && !viewModel.isDemoMode)

            Button {
                activeModal = .onboarding
            } label: {
                quickLinkRow(
                    title: "Relancer l'assistant d'installation",
                    subtitle: "Assistant en 4 étapes (Bonjour, Sécurité, Services, Résumé)",
                    systemImage: "wand.and.stars",
                    tint: .indigo
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var quickLinksSection: some View {
        Section("Outils & Configuration avancée") {
            Button {
                activeModal = .notifications
            } label: {
                quickLinkRow(
                    title: "Notifications & Alertes (APNs / Webhooks)",
                    subtitle: "Permissions Apple, APNs serveur, Discord, Telegram, ntfy",
                    systemImage: "bell.badge.fill",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)

            Button {
                activeModal = .yamlEditor
            } label: {
                quickLinkRow(
                    title: "Éditeur YAML & Rechargement à chaud",
                    subtitle: "Consulter, valider, modifier et exporter config.yaml",
                    systemImage: "doc.text.magnifyingglass",
                    tint: DesignTokens.accent(viewModel.accentTheme, colorScheme)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.serverBaseURL.isEmpty && !viewModel.isDemoMode)

            Button {
                activeModal = .appleTVPairing
            } label: {
                quickLinkRow(
                    title: "Appairage Apple TV (PIN 6 chiffres)",
                    subtitle: "Transfert chiffré CryptoKit P-256 + AES-GCM",
                    systemImage: "appletv.fill",
                    tint: DesignTokens.accent(viewModel.accentTheme, colorScheme)
                )
            }
            .buttonStyle(.plain)

            Button {
                activeModal = .onboarding
            } label: {
                quickLinkRow(
                    title: "Relancer l'assistant d'installation",
                    subtitle: "Assistant en 4 étapes (Bonjour, Sécurité, Services, Résumé)",
                    systemImage: "wand.and.stars",
                    tint: .indigo
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func quickLinkRow(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var savedServersSection: some View {
        Section("Serveurs enregistrés (\(viewModel.savedServers.count))") {
            ForEach(viewModel.savedServers) { server in
                let isActive = !viewModel.isDemoMode
                    && server.baseURL.caseInsensitiveCompare(viewModel.serverBaseURL) == .orderedSame
                let hasToken = viewModel.keychainStore.readBearerToken(profileID: server.id) != nil

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.setActiveServer(server)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "server.rack")
                                .foregroundStyle(isActive ? .green : DesignTokens.accent(viewModel.accentTheme, colorScheme))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(server.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if isActive {
                                        Text("Actif")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.green.opacity(0.2), in: Capsule())
                                            .foregroundStyle(.green)
                                    }
                                    if server.usesTailscaleSSO {
                                        let accent = DesignTokens.accent(viewModel.accentTheme, colorScheme)
                                        Text("SSO")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(accent.opacity(0.16), in: Capsule())
                                            .foregroundStyle(accent)
                                    }
                                    if hasToken {
                                        Image(systemName: "key.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .accessibilityLabel("Jeton stocké dans le Trousseau")
                                    }
                                }
                                Text(server.baseURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        viewModel.removeServer(id: server.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Supprimer \(server.name)")
                }
            }

            if viewModel.activeServerProfile != nil && !viewModel.isDemoMode {
                HStack(spacing: 8) {
                    SecureField(
                        viewModel.hasActiveToken ? "Mettre à jour le jeton Bearer actif" : "Ajouter un jeton Bearer (Trousseau)",
                        text: $activeTokenEdit
                    )
                    Button("Appliquer") {
                        Task {
                            await viewModel.saveBearerToken(activeTokenEdit)
                            activeTokenEdit = ""
                            await viewModel.refreshAll(silent: false)
                        }
                    }
                    .buttonStyle(.bordered)
                    .adaptiveSmallControlSize()
                    .disabled(activeTokenEdit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if viewModel.hasActiveToken {
                        Button(role: .destructive) {
                            Task { await viewModel.clearBearerToken() }
                        } label: {
                            Image(systemName: "key.slash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Effacer le jeton du Trousseau")
                    }
                }
            }
        }
    }

    private var bonjourDiscoverySection: some View {
        Section("Découverte locale Bonjour (_pvecenter._tcp)") {
            ForEach(viewModel.discoveryService.pveServers) { server in
                Button {
                    urlInput = server.resolvedBaseUrl
                    serverNameInput = server.name
                    Task { await verifyAndAddServer() }
                } label: {
                    HStack {
                        Image(systemName: "bonjour")
                            .foregroundStyle(DesignTokens.accent(viewModel.accentTheme, colorScheme))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(server.resolvedBaseUrl)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("Connecter")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.accent(viewModel.accentTheme, colorScheme))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var addServerSection: some View {
        Section("Ajouter ou connecter un serveur") {
            TextField("Nom du serveur (ex: Homelab principal)", text: $serverNameInput)
                .autocorrectionDisabled()

            TextField("https://pve-panel.votre-tailnet.ts.net ou IP locale", text: $urlInput)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

            SecureField("Jeton Bearer API (optionnel si Tailscale SSO)", text: $tokenInput)

            #if os(iOS)
            Button {
                activeModal = .qrScanner
            } label: {
                Label("Scanner un QR Code de connexion", systemImage: "qrcode.viewfinder")
            }
            #endif

            Button {
                Task { await verifyAndAddServer() }
            } label: {
                HStack {
                    Label("Tester et connecter", systemImage: "checkmark.shield.fill")
                    Spacer()
                    if testing {
                        ProgressView()
                    }
                }
            }
            .disabled(testing || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let statusBanner {
                Label(
                    statusBanner.text,
                    systemImage: statusBanner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(statusBanner.isError ? .red : .green)
            }
        }
    }

    private var deepLinkPairingSection: some View {
        Section("Appairage rapide (Deep-Link)") {
            TextField("pvecenter://connect?url=https://...&name=...", text: $deepLinkInput)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

            Button {
                Task { await importDeepLink() }
            } label: {
                Label("Importer le lien d'appairage", systemImage: "link.badge.plus")
            }
            .disabled(testing || deepLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var proxmoxTailscaleQuickSection: some View {
        Section("Proxmox VE & Tailscale (Configuration rapide)") {
            if let status = viewModel.setupStatus {
                if !status.env.pveHost.isEmpty {
                    LabeledContent("Hôte Proxmox", value: status.env.pveHost)
                        .font(.caption)
                }
                if !status.env.pveNode.isEmpty {
                    LabeledContent("Nœud PVE", value: status.env.pveNode)
                        .font(.caption)
                }
                if !status.tailscaleUrl.isEmpty {
                    LabeledContent("Tailscale Serve", value: status.tailscaleUrl)
                        .font(.caption)
                }
                if !status.env.allowedTailscaleUsers.isEmpty {
                    LabeledContent("Utilisateurs autorisés", value: status.env.allowedTailscaleUsers)
                        .font(.caption)
                }
            }

            Button {
                activeModal = .setupWizard
            } label: {
                HStack {
                    Label("Configurer Proxmox, Tailscale & Médias…", systemImage: "slider.horizontal.3")
                    Spacer()
                    if let configured = viewModel.setupStatus?.isConfigured, !configured {
                        Text("À configurer")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(viewModel.serverBaseURL.isEmpty && !viewModel.isDemoMode)
        }
    }

    private var demoModeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Mode Démo interactif (App Store Review)", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.indigo)
                Text("Explorez toutes les vues SwiftUI, graphiques Swift Charts et l'assistant de configuration hors-ligne sans VPN Tailscale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        await viewModel.configureConnection(baseURL: urlInput, demoMode: true)
                        dismiss()
                    }
                } label: {
                    Label(
                        viewModel.isDemoMode ? "Mode Démo déjà actif" : "Activer le Mode Démo",
                        systemImage: "play.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .adaptivePillButtonStyle(tint: .indigo, prominent: true, cornerRadius: 12)
            }
            .padding(.vertical, 4)
        }
    }

    private var refreshOptionsSection: some View {
        Section("Synchronisation & Temps réel") {
            LabeledContent("Flux temps réel", value: viewModel.realtimeState.label)
                .font(.caption)

            Toggle(
                "Actualisation automatique (5s)",
                isOn: Binding(
                    get: { viewModel.autoRefresh },
                    set: { _ in viewModel.toggleAutoRefresh() }
                )
            )
            if let last = viewModel.lastUpdated {
                HStack {
                    Text("Dernière synchronisation")
                    Spacer()
                    Text(last.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Actions

    private func serverURLInputApply(_ scanned: QRScannedConnection) {
        urlInput = scanned.baseURL
        if serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            serverNameInput = scanned.serverName
        }
        if let token = scanned.token, !token.isEmpty {
            tokenInput = token
        }
        Task { await verifyAndAddServer() }
    }

    private func verifyAndAddServer() async {
        testing = true
        statusBanner = nil

        var targetURL = urlInput
        var targetName = serverNameInput
        var targetToken: String? = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if targetToken?.isEmpty == true { targetToken = nil }

        if let url = URL(string: urlInput.trimmingCharacters(in: .whitespacesAndNewlines)),
           let parsed = AppViewModel.parseConnectDeepLinkPayload(url: url) {
            targetURL = parsed.url
            if targetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                targetName = parsed.name
            }
            if targetToken == nil {
                targetToken = parsed.token
            }
        }

        do {
            let user = try await viewModel.testConnection(candidateURL: targetURL, bearerToken: targetToken)
            statusBanner = (false, "Connecté en tant que \(user.login).")
            await viewModel.addOrSelectServer(
                name: targetName,
                baseURL: targetURL,
                bearerToken: targetToken,
                usesTailscaleSSO: targetToken == nil
            )
            dismiss()
        } catch {
            statusBanner = (true, error.localizedDescription)
        }
        testing = false
    }

    private func importDeepLink() async {
        let trimmed = deepLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), AppViewModel.parseConnectDeepLink(url: url) != nil else {
            statusBanner = (true, "Lien pvecenter://connect?url=... invalide.")
            return
        }
        testing = true
        statusBanner = nil
        await viewModel.handleIncomingURL(url)
        testing = false
        if viewModel.connectionError == nil {
            dismiss()
        } else {
            statusBanner = (true, viewModel.connectionError ?? "Connexion impossible.")
        }
    }
}
