import SwiftUI

public struct ServerSetupWizardSheet: View {
    public var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isConfigured: Bool = false
    @State private var detectedTailscaleURL: String = ""
    @State private var pairingDeepLink: String = ""

    // Proxmox VE
    @State private var pveHost: String = ""
    @State private var pveNode: String = "pve"
    @State private var pveTokenId: String = ""
    @State private var pveTokenSecret: String = ""
    @State private var pveTokenSecretSet: Bool = false
    @State private var pveVerifySsl: Bool = false
    @State private var panelSelfVmidText: String = "116"

    // Tailscale & Owner Security
    @State private var allowedTailscaleUsers: String = ""
    @State private var protectedOwnerUsername: String = "admin"
    @State private var devAuthBypass: Bool = false

    // Media & Download Services
    @State private var jellyfinUrl: String = ""
    @State private var jellyfinApiKey: String = ""
    @State private var jellyfinApiKeySet: Bool = false

    @State private var jellyseerrUrl: String = ""
    @State private var jellyseerrApiKey: String = ""
    @State private var jellyseerrApiKeySet: Bool = false

    @State private var plexUrl: String = ""
    @State private var plexToken: String = ""
    @State private var plexTokenSet: Bool = false

    @State private var stremioUrl: String = ""
    @State private var stremioUsername: String = "admin"
    @State private var stremioPassword: String = ""
    @State private var stremioPasswordSet: Bool = false

    @State private var radarrUrl: String = ""
    @State private var radarrApiKey: String = ""
    @State private var radarrApiKeySet: Bool = false

    @State private var sonarrUrl: String = ""
    @State private var sonarrApiKey: String = ""
    @State private var sonarrApiKeySet: Bool = false

    @State private var prowlarrUrl: String = ""
    @State private var prowlarrApiKey: String = ""
    @State private var prowlarrApiKeySet: Bool = false

    @State private var qbitUrl: String = ""
    @State private var qbitUsername: String = ""
    @State private var qbitPassword: String = ""
    @State private var qbitPasswordSet: Bool = false

    // Live per-service test state
    @State private var testingService: String?
    @State private var testResults: [String: ServiceTestResponse] = [:]
    @State private var showOnboardingFlow: Bool = false
    @State private var showYAMLEditor: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            #if os(tvOS)
            tvOSWizardBody
                .fullScreenCover(isPresented: $showOnboardingFlow) {
                    OnboardingFlowView(viewModel: viewModel)
                        .environment(\.accentTheme, viewModel.accentTheme)
                        .tint(viewModel.tintColor(for: .dark))
                        .preferredColorScheme(.dark)
                }
                .fullScreenCover(isPresented: $showYAMLEditor) {
                    YAMLConfigEditorView(viewModel: viewModel)
                        .environment(\.accentTheme, viewModel.accentTheme)
                        .tint(viewModel.tintColor(for: .dark))
                        .preferredColorScheme(.dark)
                }
            #else
            standardWizardBody
                .sheet(isPresented: $showOnboardingFlow) {
                    OnboardingFlowView(viewModel: viewModel)
                        .environment(\.accentTheme, viewModel.accentTheme)
                        .tint(viewModel.tintColor(for: colorScheme))
                        .preferredColorScheme(viewModel.preferredColorScheme)
                }
                .sheet(isPresented: $showYAMLEditor) {
                    YAMLConfigEditorView(viewModel: viewModel)
                        .environment(\.accentTheme, viewModel.accentTheme)
                        .tint(viewModel.tintColor(for: colorScheme))
                        .preferredColorScheme(viewModel.preferredColorScheme)
                }
            #endif
        }
        #if os(tvOS)
        .preferredColorScheme(.dark)
        #else
        .preferredColorScheme(viewModel.preferredColorScheme)
        #endif
    }

    #if os(tvOS)
    private var tvOSWizardBody: some View {
        ZStack {
            AmbientBackgroundView()

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Configuration Serveur")
                            .font(.largeTitle.weight(.bold))
                        Text(isConfigured ? "Serveur configuré (\(viewModel.activeServerName))" : "Configuration initiale requise (\(viewModel.activeServerName))")
                            .font(.callout)
                            .foregroundStyle(isConfigured ? .green : .orange)
                    }
                    Spacer()
                    Button {
                        showOnboardingFlow = true
                    } label: {
                        Label("Assistant 4 étapes", systemImage: "wand.and.stars")
                            .font(.callout.weight(.semibold))
                    }
                    .adaptivePillButtonStyle()

                    Button {
                        showYAMLEditor = true
                    } label: {
                        Label("YAML", systemImage: "doc.text")
                            .font(.callout.weight(.semibold))
                    }
                    .adaptivePillButtonStyle()

                    Button {
                        guard !(isLoading || isSaving) else { return }
                        Task { await saveConfig() }
                    } label: {
                        Text(isSaving ? "Application…" : "Enregistrer")
                            .font(.callout.weight(.semibold))
                            .opacity((isLoading || isSaving) ? 0.5 : 1.0)
                    }
                    .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)

                    Button {
                        dismiss()
                    } label: {
                        Label("Fermer", systemImage: "xmark.circle.fill")
                            .font(.callout.weight(.semibold))
                    }
                    .adaptivePillButtonStyle()
                }
                .padding(.horizontal, 48)
                .padding(.top, 32)
                .padding(.bottom, 16)
                .focusSection()

                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView("Chargement de la configuration du serveur…")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 760), spacing: 28)], spacing: 24) {
                            GlassCard(padding: 24, cornerRadius: 22) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Proxmox VE & Sécurité")
                                        .font(.title3.weight(.semibold))
                                    TextField("Hôte Proxmox (https://192.168.1.10:8006)", text: $pveHost)
                                    TextField("Nom du nœud (ex: pve)", text: $pveNode)
                                    TextField("Token ID (ex: root@pam!pve-panel)", text: $pveTokenId)
                                    SecureField(
                                        pveTokenSecretSet ? "Secret défini (laisser vide pour conserver)" : "Secret du token API",
                                        text: $pveTokenSecret
                                    )
                                    TextField("VMID du conteneur panel (ex: 116)", text: $panelSelfVmidText)
                                    Toggle("Vérifier le certificat SSL Proxmox", isOn: $pveVerifySsl)
                                    testButtonAndResult(serviceKey: "proxmox", title: "Tester Proxmox VE") {
                                        ServiceTestRequest(
                                            service: "proxmox",
                                            url: pveHost,
                                            node: pveNode,
                                            tokenId: pveTokenId,
                                            secret: nonEmptyOrNil(pveTokenSecret),
                                            verifySsl: pveVerifySsl
                                        )
                                    }
                                    .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme))
                                    Divider()
                                    TextField("Emails Tailscale autorisés", text: $allowedTailscaleUsers)
                                    TextField("Compte propriétaire protégé", text: $protectedOwnerUsername)
                                    Toggle("Bypass auth locale (DEV uniquement)", isOn: $devAuthBypass)
                                }
                            }

                            GlassCard(padding: 24, cornerRadius: 22) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Services Médias & Téléchargements")
                                        .font(.title3.weight(.semibold))
                                    TextField("URL Jellyfin", text: $jellyfinUrl)
                                    SecureField(jellyfinApiKeySet ? "Clé API Jellyfin (définie)" : "Clé API Jellyfin", text: $jellyfinApiKey)
                                    TextField("URL Jellyseerr", text: $jellyseerrUrl)
                                    SecureField(jellyseerrApiKeySet ? "Clé API Jellyseerr (définie)" : "Clé API Jellyseerr", text: $jellyseerrApiKey)
                                    TextField("URL Plex", text: $plexUrl)
                                    SecureField(plexTokenSet ? "Token Plex (défini)" : "Token Plex", text: $plexToken)
                                    TextField("URL Stremio", text: $stremioUrl)
                                    TextField("Utilisateur Stremio", text: $stremioUsername)
                                    SecureField(stremioPasswordSet ? "Mot de passe Stremio (défini)" : "Mot de passe Stremio", text: $stremioPassword)
                                    TextField("URL Radarr", text: $radarrUrl)
                                    SecureField(radarrApiKeySet ? "Clé API Radarr (définie)" : "Clé API Radarr", text: $radarrApiKey)
                                    TextField("URL Sonarr", text: $sonarrUrl)
                                    SecureField(sonarrApiKeySet ? "Clé API Sonarr (définie)" : "Clé API Sonarr", text: $sonarrApiKey)
                                    TextField("URL Prowlarr", text: $prowlarrUrl)
                                    SecureField(prowlarrApiKeySet ? "Clé API Prowlarr (définie)" : "Clé API Prowlarr", text: $prowlarrApiKey)
                                    TextField("URL qBittorrent", text: $qbitUrl)
                                    TextField("Utilisateur qBittorrent", text: $qbitUsername)
                                    SecureField(qbitPasswordSet ? "Mot de passe qBittorrent (défini)" : "Mot de passe qBittorrent", text: $qbitPassword)
                                }
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.top, 12)
                        .padding(.bottom, 36)
                    }
                }
            }
        }
        .task {
            await loadStatus()
        }
    }
    #endif

    private var standardWizardBody: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView("Chargement de la configuration du serveur…")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        if let loadError {
                            Section {
                                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                Button("Réessayer") {
                                    Task { await loadStatus() }
                                }
                            }
                        }

                        if let saveError {
                            Section {
                                Label(saveError, systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }

                        statusHeaderSection
                        proxmoxSection
                        securitySection

                        mediaServiceSection(
                            title: "Jellyfin",
                            serviceKey: "jellyfin",
                            urlPlaceholder: "http://192.168.1.26:8096",
                            url: $jellyfinUrl,
                            secretLabel: "Clé API Jellyfin",
                            secret: $jellyfinApiKey,
                            secretAlreadySet: jellyfinApiKeySet
                        )

                        mediaServiceSection(
                            title: "Jellyseerr",
                            serviceKey: "jellyseerr",
                            urlPlaceholder: "http://192.168.1.31:5055",
                            url: $jellyseerrUrl,
                            secretLabel: "Clé API Jellyseerr",
                            secret: $jellyseerrApiKey,
                            secretAlreadySet: jellyseerrApiKeySet
                        )

                        mediaServiceSection(
                            title: "Plex",
                            serviceKey: "plex",
                            urlPlaceholder: "http://192.168.1.30:32400",
                            url: $plexUrl,
                            secretLabel: "Token Plex (X-Plex-Token)",
                            secret: $plexToken,
                            secretAlreadySet: plexTokenSet
                        )

                        mediaServiceSection(
                            title: "Stremio (Web + Server)",
                            serviceKey: "stremio",
                            urlPlaceholder: "http://192.168.1.33:8080",
                            url: $stremioUrl,
                            username: $stremioUsername,
                            secretLabel: "Mot de passe Basic Auth (optionnel)",
                            secret: $stremioPassword,
                            secretAlreadySet: stremioPasswordSet
                        )

                        mediaServiceSection(
                            title: "Radarr",
                            serviceKey: "radarr",
                            urlPlaceholder: "http://192.168.1.27:7878",
                            url: $radarrUrl,
                            secretLabel: "Clé API Radarr",
                            secret: $radarrApiKey,
                            secretAlreadySet: radarrApiKeySet
                        )

                        mediaServiceSection(
                            title: "Sonarr",
                            serviceKey: "sonarr",
                            urlPlaceholder: "http://192.168.1.28:8989",
                            url: $sonarrUrl,
                            secretLabel: "Clé API Sonarr",
                            secret: $sonarrApiKey,
                            secretAlreadySet: sonarrApiKeySet
                        )

                        mediaServiceSection(
                            title: "Prowlarr",
                            serviceKey: "prowlarr",
                            urlPlaceholder: "http://192.168.1.29:9696",
                            url: $prowlarrUrl,
                            secretLabel: "Clé API Prowlarr",
                            secret: $prowlarrApiKey,
                            secretAlreadySet: prowlarrApiKeySet
                        )

                        mediaServiceSection(
                            title: "qBittorrent",
                            serviceKey: "qbittorrent",
                            urlPlaceholder: "http://192.168.1.32:8090",
                            url: $qbitUrl,
                            username: $qbitUsername,
                            secretLabel: "Mot de passe qBittorrent",
                            secret: $qbitPassword,
                            secretAlreadySet: qbitPasswordSet
                        )

                        Section {
                            Button {
                                Task { await saveConfig() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isSaving {
                                        ProgressView()
                                    } else {
                                        Label("Enregistrer & Appliquer à chaud", systemImage: "checkmark.circle.fill")
                                            .font(.headline)
                                    }
                                    Spacer()
                                }
                            }
                            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true, cornerRadius: 12)
                            .disabled(isSaving)
                        }
                    }
                    .formStyle(.grouped)
                    #if !os(tvOS)
                    .scrollContentBackground(.hidden)
                    #endif
                    .background { AmbientBackgroundView() }
                }
            }
            .navigationTitle("Configuration Serveur")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Application…" : "Enregistrer") {
                        Task { await saveConfig() }
                    }
                    .disabled(isLoading || isSaving)
                }
            }
            .task {
                await loadStatus()
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 580)
        #endif
    }

    // MARK: - Sections

    private var statusHeaderSection: some View {
        Section("État du serveur (\(viewModel.activeServerName))") {
            HStack {
                Label(
                    isConfigured ? "Serveur configuré" : "Configuration initiale requise",
                    systemImage: isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(isConfigured ? .green : .orange)
                Spacer()
                if viewModel.isDemoMode {
                    Text("Démo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
            }

            if !detectedTailscaleURL.isEmpty {
                LabeledContent("URL Tailscale", value: detectedTailscaleURL)
                    .font(.caption)
            }

            if !pairingDeepLink.isEmpty {
                LabeledContent("Lien d'appairage", value: pairingDeepLink)
                    .font(.caption2)
            }

            Button {
                showOnboardingFlow = true
            } label: {
                Label("Ouvrir l'assistant guidé (4 étapes)", systemImage: "wand.and.stars")
            }

            Button {
                showYAMLEditor = true
            } label: {
                Label("Ouvrir l'éditeur YAML avancé", systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    private var proxmoxSection: some View {
        Section("Proxmox VE") {
            TextField("Hôte Proxmox (https://192.168.1.10:8006)", text: $pveHost)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

            TextField("Nom du nœud (ex: pve)", text: $pveNode)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            TextField("Token ID (ex: root@pam!pve-panel)", text: $pveTokenId)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            SecureField(
                pveTokenSecretSet ? "Secret défini (laisser vide pour conserver)" : "Secret du token API",
                text: $pveTokenSecret
            )

            TextField("VMID du conteneur panel (ex: 116)", text: $panelSelfVmidText)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif

            Toggle("Vérifier le certificat SSL Proxmox", isOn: $pveVerifySsl)

            testButtonAndResult(serviceKey: "proxmox", title: "Tester Proxmox VE") {
                ServiceTestRequest(
                    service: "proxmox",
                    url: pveHost,
                    node: pveNode,
                    tokenId: pveTokenId,
                    secret: nonEmptyOrNil(pveTokenSecret),
                    verifySsl: pveVerifySsl
                )
            }
        }
    }

    private var securitySection: some View {
        Section("Sécurité Tailscale & Propriétaire") {
            TextField("Emails Tailscale autorisés (séparés par virgules)", text: $allowedTailscaleUsers)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif

            TextField("Compte propriétaire protégé (ex: admin)", text: $protectedOwnerUsername)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            Toggle("Bypass auth locale (DEV uniquement)", isOn: $devAuthBypass)
        }
    }

    private func mediaServiceSection(
        title: String,
        serviceKey: String,
        urlPlaceholder: String,
        url: Binding<String>,
        username: Binding<String>? = nil,
        secretLabel: String,
        secret: Binding<String>,
        secretAlreadySet: Bool
    ) -> some View {
        Section(title) {
            TextField("URL \(title) (\(urlPlaceholder))", text: url)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

            if let username {
                TextField("Nom d'utilisateur", text: username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            SecureField(
                secretAlreadySet ? "\(secretLabel) (déjà définie — laisser vide pour conserver)" : secretLabel,
                text: secret
            )

            testButtonAndResult(serviceKey: serviceKey, title: "Tester \(title)") {
                ServiceTestRequest(
                    service: serviceKey,
                    url: url.wrappedValue,
                    secret: nonEmptyOrNil(secret.wrappedValue),
                    username: username.flatMap { nonEmptyOrNil($0.wrappedValue) }
                )
            }
        }
    }

    @ViewBuilder
    private func testButtonAndResult(
        serviceKey: String,
        title: String,
        buildRequest: @escaping () -> ServiceTestRequest
    ) -> some View {
        Button {
            guard testingService == nil else { return }
            Task { await runServiceTest(buildRequest()) }
        } label: {
            HStack {
                Label(title, systemImage: "network")
                Spacer()
                if testingService == serviceKey {
                    ProgressView()
                }
            }
            #if os(tvOS)
            .opacity(testingService != nil ? 0.55 : 1.0)
            #endif
        }
        #if !os(tvOS)
        .disabled(testingService != nil)
        #endif

        if let result = testResults[serviceKey] {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.ok ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(result.ok ? .green : .red)
                    if let ms = result.latencyMs {
                        Text(String(format: "Latence : %.0f ms", ms))
                            #if os(tvOS)
                            .font(.caption)
                            #else
                            .font(.caption2)
                            #endif
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Data & Actions

    private func loadStatus() async {
        isLoading = true
        loadError = nil
        do {
            let status = try await viewModel.fetchSetupStatus()
            isConfigured = status.isConfigured
            detectedTailscaleURL = status.tailscaleUrl
            pairingDeepLink = status.pairingDeepLink

            let env = status.env
            pveHost = env.pveHost
            pveNode = env.pveNode
            pveTokenId = env.pveTokenId
            pveTokenSecretSet = env.pveTokenSecretSet
            pveVerifySsl = env.pveVerifySsl
            panelSelfVmidText = String(env.panelSelfVmid)

            allowedTailscaleUsers = env.allowedTailscaleUsers
            protectedOwnerUsername = env.protectedOwnerUsername
            devAuthBypass = env.devAuthBypass

            jellyfinUrl = env.jellyfinUrl
            jellyfinApiKeySet = env.jellyfinApiKeySet

            jellyseerrUrl = env.jellyseerrUrl
            jellyseerrApiKeySet = env.jellyseerrApiKeySet

            plexUrl = env.plexUrl
            plexTokenSet = env.plexTokenSet

            stremioUrl = env.stremioUrl
            stremioUsername = env.stremioUsername.isEmpty ? "admin" : env.stremioUsername
            stremioPasswordSet = env.stremioPasswordSet

            radarrUrl = env.radarrUrl
            radarrApiKeySet = env.radarrApiKeySet

            sonarrUrl = env.sonarrUrl
            sonarrApiKeySet = env.sonarrApiKeySet

            prowlarrUrl = env.prowlarrUrl
            prowlarrApiKeySet = env.prowlarrApiKeySet

            qbitUrl = env.qbitUrl
            qbitUsername = env.qbitUsername
            qbitPasswordSet = env.qbitPasswordSet
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func runServiceTest(_ request: ServiceTestRequest) async {
        testingService = request.service
        do {
            let response = try await viewModel.testSetupService(request)
            testResults[request.service] = response
        } catch {
            testResults[request.service] = ServiceTestResponse(
                ok: false,
                service: request.service,
                message: error.localizedDescription,
                latencyMs: nil
            )
        }
        testingService = nil
    }

    private func saveConfig() async {
        isSaving = true
        saveError = nil

        let vmid = Int(panelSelfVmidText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 116
        let envUpdate = SetupEnvUpdate(
            devAuthBypass: devAuthBypass,
            allowedTailscaleUsers: allowedTailscaleUsers.trimmingCharacters(in: .whitespacesAndNewlines),
            protectedOwnerUsername: protectedOwnerUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            pveHost: pveHost.trimmingCharacters(in: .whitespacesAndNewlines),
            pveNode: pveNode.trimmingCharacters(in: .whitespacesAndNewlines),
            pveTokenId: pveTokenId.trimmingCharacters(in: .whitespacesAndNewlines),
            pveTokenSecret: nonEmptyOrNil(pveTokenSecret),
            pveVerifySsl: pveVerifySsl,
            panelSelfVmid: vmid,
            jellyfinUrl: jellyfinUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            jellyfinApiKey: nonEmptyOrNil(jellyfinApiKey),
            jellyseerrUrl: jellyseerrUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            jellyseerrApiKey: nonEmptyOrNil(jellyseerrApiKey),
            plexUrl: plexUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            plexToken: nonEmptyOrNil(plexToken),
            stremioUrl: stremioUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            stremioUsername: stremioUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            stremioPassword: nonEmptyOrNil(stremioPassword),
            radarrUrl: radarrUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            radarrApiKey: nonEmptyOrNil(radarrApiKey),
            sonarrUrl: sonarrUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            sonarrApiKey: nonEmptyOrNil(sonarrApiKey),
            prowlarrUrl: prowlarrUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            prowlarrApiKey: nonEmptyOrNil(prowlarrApiKey),
            qbitUrl: qbitUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            qbitUsername: qbitUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            qbitPassword: nonEmptyOrNil(qbitPassword)
        )

        do {
            _ = try await viewModel.saveSetupConfig(SetupConfigUpdateRequest(env: envUpdate))
            isSaving = false
            dismiss()
        } catch {
            saveError = error.localizedDescription
            isSaving = false
        }
    }

    private func nonEmptyOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
