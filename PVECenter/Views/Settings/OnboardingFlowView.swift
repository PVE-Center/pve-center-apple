import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case connection = 0
    case security = 1
    case servicesAndAlerts = 2
    case finalize = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .connection: "Connexion"
        case .security: "Sécurité"
        case .servicesAndAlerts: "Services & Alertes"
        case .finalize: "Finalisation"
        }
    }

    public var systemImage: String {
        switch self {
        case .connection: "antenna.radiowaves.left.and.right"
        case .security: "lock.shield.fill"
        case .servicesAndAlerts: "square.stack.3d.up.fill"
        case .finalize: "checkmark.seal.fill"
        }
    }
}

private enum OnboardingAuthChoice: String, CaseIterable, Identifiable {
    case tailscaleSSO
    case bearerToken
    case adminPIN

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tailscaleSSO: "Tailscale SSO"
        case .bearerToken: "Jeton Bearer"
        case .adminPIN: "Code PIN Admin"
        }
    }
}

private struct HomelabTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let category: String
    let icon: String
    let `protocol`: CustomServiceProtocol
    let defaultPort: Int
    let defaultPath: String
    let useHttps: Bool

    static let presets: [HomelabTemplate] = [
        HomelabTemplate(
            id: "proxmox-ve",
            name: "Proxmox VE",
            description: "Interface web et API de l'hyperviseur",
            category: "Infrastructure & Sécurité",
            icon: "server",
            protocol: .httpRest,
            defaultPort: 8006,
            defaultPath: "",
            useHttps: true
        ),
        HomelabTemplate(
            id: "jellyfin",
            name: "Jellyfin",
            description: "Serveur multimédia & streaming",
            category: "Médias & Streaming",
            icon: "film",
            protocol: .httpRest,
            defaultPort: 8096,
            defaultPath: "/health",
            useHttps: false
        ),
        HomelabTemplate(
            id: "adguard-home",
            name: "AdGuard Home",
            description: "Filtrage DNS réseau local",
            category: "Infrastructure & Sécurité",
            icon: "shield",
            protocol: .httpRest,
            defaultPort: 3000,
            defaultPath: "",
            useHttps: false
        ),
        HomelabTemplate(
            id: "home-assistant",
            name: "Home Assistant",
            description: "Domotique locale & capteurs",
            category: "Domotique",
            icon: "house",
            protocol: .httpRest,
            defaultPort: 8123,
            defaultPath: "/api/",
            useHttps: false
        ),
        HomelabTemplate(
            id: "grafana",
            name: "Grafana",
            description: "Tableaux de bord et métriques",
            category: "Supervision",
            icon: "chart.bar.doc.horizontal",
            protocol: .httpRest,
            defaultPort: 3000,
            defaultPath: "/api/health",
            useHttps: false
        ),
    ]
}

public struct OnboardingFlowView: View {
    public var viewModel: AppViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var currentStep: OnboardingStep = .connection

    // Step 1: Connexion
    @State private var serverNameInput: String = ""
    @State private var serverURLInput: String = ""
    @State private var deepLinkInput: String = ""
    @State private var authChoice: OnboardingAuthChoice = .tailscaleSSO
    @State private var isTestingConnection: Bool = false
    @State private var connectionProbeOK: Bool = false
    @State private var connectionProbeMessage: String?
    @State private var onboardingStatus: OnboardingStatusResponse?
    @State private var showQRScanner: Bool = false
    @State private var showAppleTVPairing: Bool = false
    @State private var showDeepLinkImport: Bool = false

    // Step 2: Sécurité
    @State private var initializeNewServer: Bool = true
    @State private var tokenNameInput: String = Self.defaultTokenLabel()
    @State private var adminPinInput: String = ""
    @State private var tailscaleSSOEnabled: Bool = true
    @State private var allowedTailscaleUsers: String = ""
    @State private var optionalPveHost: String = ""
    @State private var optionalPveNode: String = "pve"
    @State private var optionalPveTokenId: String = ""
    @State private var optionalPveTokenSecret: String = ""
    @State private var showOptionalProxmox: Bool = false

    @State private var bearerTokenInput: String = ""
    @State private var generatedOneTimeToken: String?
    @State private var tokenCopied: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var authVerifiedMessage: String?
    @State private var authErrorMessage: String?

    // Step 3: Services & Alertes
    @State private var stagedServices: [CustomServiceConfig] = []
    @State private var serviceTestResults: [String: CustomServiceTestResult] = [:]
    @State private var testingServiceID: String?
    @State private var extraServerLANDiscovery: [DiscoveryServerItem] = []

    @State private var templateHostInput: String = "192.168.1.10"
    @State private var showManualServiceForm: Bool = false
    @State private var manualSvcName: String = ""
    @State private var manualSvcProtocol: CustomServiceProtocol = .httpRest
    @State private var manualSvcURL: String = ""
    @State private var manualSvcHost: String = ""
    @State private var manualSvcPortText: String = "80"
    @State private var manualSvcAlertsEnabled: Bool = true

    @State private var pushNotificationsOptIn: Bool = false

    // Step 4: Finalisation
    @State private var isFinalizing: Bool = false
    @State private var finalizeError: String?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var normalizedServerURL: String {
        APIClient.normalizeBaseURL(serverURLInput)
    }

    private var resolvedServerName: String {
        let trimmed = serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let name = onboardingStatus?.serverName, !name.isEmpty { return name }
        if let host = URL(string: normalizedServerURL)?.host, !host.isEmpty {
            return host.split(separator: ".").first.map(String.init) ?? host
        }
        return "Mon Homelab"
    }

    private var effectiveBearerToken: String? {
        let gen = generatedOneTimeToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let gen, !gen.isEmpty { return gen }
        let manual = bearerTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return manual.isEmpty ? nil : manual
    }

    private var combinedLANDiscoveryItems: [DiscoveryServerItem] {
        var merged: [DiscoveryServerItem] = []
        var seen: Set<String> = []
        for item in viewModel.lanDiscoveryItems + extraServerLANDiscovery {
            let key = "\(item.serviceType.lowercased())|\(item.host.lowercased())|\(item.port)"
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }
        return merged
    }

    public var body: some View {
        NavigationStack {
            Group {
                #if os(tvOS)
                tvOSWizardLayout
                #else
                standardWizardLayout
                #endif
            }
            .navigationTitle("Assistant PVE Center")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !viewModel.savedServers.isEmpty || viewModel.isDemoMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") {
                            viewModel.dismissOnboarding()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Mode Démo") {
                        Task { await enterDemoMode() }
                    }
                }
            }
            #if os(tvOS)
            .preferredColorScheme(.dark)
            .fullScreenCover(isPresented: $showAppleTVPairing) {
                AppleTVPairingView(viewModel: viewModel, initialMode: .receiver) { _ in
                    viewModel.dismissOnboarding()
                    dismiss()
                }
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
            }
            #else
            .sheet(isPresented: $showQRScanner) {
                QRScannerView { scanned in
                    applyScannedConnection(scanned)
                }
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
            }
            .sheet(isPresented: $showAppleTVPairing) {
                AppleTVPairingView(viewModel: viewModel, initialMode: .receiver) { _ in
                    viewModel.dismissOnboarding()
                    dismiss()
                }
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 620)
        #endif
        .onAppear {
            viewModel.discoveryService.startPVEDiscovery()
            if serverURLInput.isEmpty && !viewModel.serverBaseURL.isEmpty {
                serverURLInput = viewModel.serverBaseURL
                serverNameInput = viewModel.activeServerName
            }
            if let host = URL(string: normalizedServerURL)?.host, !host.isEmpty {
                templateHostInput = host
            }
            Task {
                await viewModel.pushManager.refreshAuthorizationStatus()
                let status = viewModel.pushManager.authorizationStatus
                pushNotificationsOptIn = (status == .authorized || status == .provisional)
            }
        }
    }

    // MARK: - iOS & macOS Wizard Shell

    #if !os(tvOS)
    private var standardWizardLayout: some View {
        VStack(spacing: 0) {
            stepProgressHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)

            Divider()

            Form {
                switch currentStep {
                case .connection:
                    step1ConnectionSections
                case .security:
                    step2SecuritySections
                case .servicesAndAlerts:
                    step3ServicesSections
                case .finalize:
                    step4FinalizeSections
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background { AmbientBackgroundView() }

            Divider()

            bottomNavigationBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }
    #endif

    // MARK: - tvOS Wizard Shell

    #if os(tvOS)
    private var tvOSWizardLayout: some View {
        ZStack {
            AmbientBackgroundView()

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Assistant PVE Center")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Text("Configuration guidée en 4 étapes")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                    Spacer()
                    Button {
                        Task { await enterDemoMode() }
                    } label: {
                        Label("Mode Démo", systemImage: "sparkles")
                            .font(.callout.weight(.semibold))
                    }
                    .adaptivePillButtonStyle(tint: .indigo, prominent: true)

                    if !viewModel.savedServers.isEmpty || viewModel.isDemoMode {
                        Button {
                            viewModel.dismissOnboarding()
                            dismiss()
                        } label: {
                            Label("Fermer", systemImage: "xmark.circle.fill")
                                .font(.callout.weight(.semibold))
                        }
                        .adaptivePillButtonStyle()
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 24)
                .focusSection()

                stepProgressHeader
                    .padding(.horizontal, 48)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch currentStep {
                        case .connection:
                            step1ConnectionTVOS
                        case .security:
                            step2SecurityTVOS
                        case .servicesAndAlerts:
                            step3ServicesTVOS
                        case .finalize:
                            step4FinalizeTVOS
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                }

                bottomNavigationBar
                    .padding(.horizontal, 48)
                    .padding(.bottom, 24)
                    .focusSection()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    #endif

    // MARK: - Step Progress & Bottom Nav

    private var stepProgressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Étape \(currentStep.rawValue + 1)/\(OnboardingStep.allCases.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(DesignTokens.accent(accentTheme, colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DesignTokens.accent(accentTheme, colorScheme).opacity(0.14), in: Capsule())

                Label(currentStep.title, systemImage: currentStep.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                    .lineLimit(1)

                Spacer()
            }

            HStack(spacing: 10) {
                ForEach(OnboardingStep.allCases) { step in
                    let isActive = step == currentStep
                    let isDone = step.rawValue < currentStep.rawValue
                    let tint: Color = isActive
                        ? DesignTokens.accent(accentTheme, colorScheme)
                        : (isDone ? DesignTokens.nominal(colorScheme) : .secondary)

                    #if os(tvOS)
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(isActive || isDone ? tint.opacity(0.24) : Color.white.opacity(0.08))
                                .frame(width: 30, height: 30)
                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(tint)
                            } else {
                                Text("\(step.rawValue + 1)")
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    .foregroundStyle(tint)
                            }
                        }

                        Text(step.title)
                            .font(.caption.weight(isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? DesignTokens.primaryText(colorScheme) : DesignTokens.secondaryText(colorScheme))
                            .lineLimit(1)

                        Capsule()
                            .fill(
                                isDone
                                    ? DesignTokens.nominal(colorScheme)
                                    : (isActive ? DesignTokens.accent(accentTheme, colorScheme) : Color.white.opacity(0.14))
                            )
                            .frame(height: isActive ? 6 : 4)
                    }
                    #else
                    Button {
                        if step.rawValue <= currentStep.rawValue {
                            currentStep = step
                        }
                    } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(isActive || isDone ? tint.opacity(0.20) : Color.secondary.opacity(0.14))
                                    .frame(width: 24, height: 24)
                                if isDone {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(tint)
                                } else {
                                    Text("\(step.rawValue + 1)")
                                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                                        .foregroundStyle(tint)
                                }
                            }

                            Capsule()
                                .fill(
                                    isDone
                                        ? DesignTokens.nominal(colorScheme)
                                        : (isActive ? DesignTokens.accent(accentTheme, colorScheme) : Color.secondary.opacity(0.22))
                                )
                                .frame(height: isActive ? 5 : 4)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Étape \(step.rawValue + 1) : \(step.title)")
                    #endif
                }
            }
        }
    }

    private var bottomNavigationBar: some View {
        HStack(spacing: 14) {
            if currentStep != .connection {
                Button {
                    if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                        currentStep = prev
                    }
                } label: {
                    Label("Précédent", systemImage: "chevron.left")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .adaptivePillButtonStyle()
            }

            Spacer()

            if currentStep == .finalize {
                let finishDisabled = isFinalizing || normalizedServerURL.isEmpty
                Button {
                    guard !finishDisabled else { return }
                    Task { await finishOnboarding() }
                } label: {
                    if isFinalizing {
                        ProgressView()
                            .adaptiveSmallControlSize()
                    } else {
                        Label("Terminer", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .opacity(finishDisabled ? 0.5 : 1.0)
                .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                #if !os(tvOS)
                .disabled(finishDisabled)
                #endif
            } else {
                let nextDisabled = currentStep == .connection && normalizedServerURL.isEmpty
                Button {
                    guard !nextDisabled else { return }
                    advanceStep()
                } label: {
                    Label("Suivant", systemImage: "chevron.right")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .opacity(nextDisabled ? 0.5 : 1.0)
                .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                #if !os(tvOS)
                .disabled(nextDisabled)
                #endif
            }
        }
    }

    // MARK: - Step 1: Connexion (Form Sections)

    #if !os(tvOS)
    @ViewBuilder
    private var step1ConnectionSections: some View {
        Section {
            if viewModel.discoveryService.pveServers.isEmpty {
                HStack(spacing: 10) {
                    if viewModel.discoveryService.isScanningPVE {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                    }
                    Text("Recherche Bonjour (_pvecenter._tcp) sur le réseau local…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.discoveryService.pveServers) { server in
                    bonjourServerRow(server)
                }
            }

            Button {
                viewModel.discoveryService.startPVEDiscovery()
            } label: {
                Label("Actualiser la découverte Bonjour", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Serveurs détectés automatiquement (Bonjour)")
        }

        Section("Connexion manuelle & Authentification") {
            TextField("Nom du serveur (ex: Homelab principal)", text: $serverNameInput)
                .autocorrectionDisabled()

            TextField("https://pve-panel.votre-tailnet.ts.net ou IP locale", text: $serverURLInput)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

            Picker("Mode d'accès préféré", selection: $authChoice) {
                ForEach(OnboardingAuthChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }

            if authChoice == .bearerToken {
                SecureField("Jeton Bearer (optionnel ici, vérifié à l'étape 2)", text: $bearerTokenInput)
            }

            Button {
                Task { await testStep1Connection() }
            } label: {
                HStack {
                    Label("Tester /api/health & statut", systemImage: "checkmark.shield")
                    Spacer()
                    if isTestingConnection {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(isTestingConnection || normalizedServerURL.isEmpty)

            if let msg = connectionProbeMessage {
                Label(msg, systemImage: connectionProbeOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(connectionProbeOK ? .green : .red)
            }
        }

        Section("Appairage rapide") {
            #if os(iOS)
            Button {
                showQRScanner = true
            } label: {
                Label("Scanner QR Code", systemImage: "qrcode.viewfinder")
            }
            #endif

            Button {
                showAppleTVPairing = true
            } label: {
                Label("Recevoir depuis iPhone (PIN 6 chiffres)", systemImage: "appletv.fill")
            }

            DisclosureGroup("Importer un lien pvecenter://", isExpanded: $showDeepLinkImport) {
                TextField("pvecenter://connect?url=https://...", text: $deepLinkInput)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                Button("Importer le lien") {
                    if let parsed = QRScannerView.parseConnectionInput(deepLinkInput) {
                        applyScannedConnection(parsed)
                        showDeepLinkImport = false
                    } else {
                        connectionProbeOK = false
                        connectionProbeMessage = "Lien pvecenter:// invalide."
                    }
                }
                .disabled(deepLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Step 2: Sécurité (Form Sections)

    @ViewBuilder
    private var step2SecuritySections: some View {
        if let status = onboardingStatus {
            Section("État détecté du serveur") {
                LabeledContent("Serveur", value: status.serverName ?? resolvedServerName)
                LabeledContent("Configuration", value: status.isConfigured ? "Déjà configuré" : "Initialisation requise")
                LabeledContent("Tailscale SSO", value: status.tailscaleSsoEnabled ? "Actif" : "Inactif")
                LabeledContent("Jetons API existants", value: status.hasApiTokens ? "Oui" : "Aucun")
            }
        }

        Section {
            Toggle("Initialiser un nouveau serveur (créer jeton admin)", isOn: $initializeNewServer)
        } header: {
            Text("Mode de configuration")
        }

        if initializeNewServer {
            Section("Créer le jeton API administrateur") {
                TextField("Nom de cet appareil / jeton", text: $tokenNameInput)
                SecureField("Code PIN Admin (4 à 8 chiffres, optionnel)", text: $adminPinInput)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Toggle("Activer Tailscale SSO (loopback / reverse proxy)", isOn: $tailscaleSSOEnabled)
                if tailscaleSSOEnabled {
                    TextField("Utilisateurs Tailscale autorisés (emails)", text: $allowedTailscaleUsers)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                }

                DisclosureGroup("Paramètres Proxmox VE (optionnel)", isExpanded: $showOptionalProxmox) {
                    TextField("Hôte Proxmox (https://192.168.1.10:8006)", text: $optionalPveHost)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Nom du nœud (ex: pve)", text: $optionalPveNode)
                    TextField("Token ID (root@pam!pve-panel)", text: $optionalPveTokenId)
                        .autocorrectionDisabled()
                    SecureField("Secret Token Proxmox", text: $optionalPveTokenSecret)
                }

                Button {
                    Task { await runOnboardingInit() }
                } label: {
                    HStack {
                        Label("Générer le jeton administrateur", systemImage: "key.fill")
                        Spacer()
                        if isAuthenticating {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true, cornerRadius: 12)
                .disabled(isAuthenticating || normalizedServerURL.isEmpty)
            }

            if let generated = generatedOneTimeToken {
                oneTimeTokenDisplaySection(generated)
            }
        } else {
            Section("Connexion à un serveur existant") {
                Picker("Méthode", selection: $authChoice) {
                    ForEach(OnboardingAuthChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)

                switch authChoice {
                case .bearerToken:
                    SecureField("Collez votre jeton API Bearer", text: $bearerTokenInput)
                    Button {
                        Task { await verifyExistingBearerToken() }
                    } label: {
                        HStack {
                            Label("Vérifier le jeton Bearer", systemImage: "checkmark.shield.fill")
                            Spacer()
                            if isAuthenticating { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isAuthenticating || bearerTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                case .adminPIN:
                    SecureField("Code PIN Admin", text: $adminPinInput)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Button {
                        Task { await signInWithPIN() }
                    } label: {
                        HStack {
                            Label("Se connecter (/api/auth/login)", systemImage: "lock.open.fill")
                            Spacer()
                            if isAuthenticating { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isAuthenticating || adminPinInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                case .tailscaleSSO:
                    Text("Utilise l'en-tête Tailscale Serve authentifié par votre tailnet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await verifyTailscaleSSO() }
                    } label: {
                        HStack {
                            Label("Vérifier l'accès Tailscale SSO", systemImage: "person.badge.shield.checkmark.fill")
                            Spacer()
                            if isAuthenticating { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isAuthenticating)
                }
            }
        }

        if let msg = authVerifiedMessage {
            Section {
                Label(msg, systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }

        if let err = authErrorMessage {
            Section {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Step 3: Services & Alertes (Form Sections)

    @ViewBuilder
    private var step3ServicesSections: some View {
        Section {
            Toggle(
                "Activer les notifications push et alertes locales",
                isOn: Binding(
                    get: { pushNotificationsOptIn },
                    set: { newValue in
                        pushNotificationsOptIn = newValue
                        if newValue {
                            Task {
                                let granted = await viewModel.requestPushAuthorization()
                                pushNotificationsOptIn = granted
                            }
                        }
                    }
                )
            )
            LabeledContent("Permission Apple", value: pushStatusLabel)
                .font(.caption)
        } header: {
            Text("Alertes en temps réel")
        }

        Section {
            Button {
                Task { await runCombinedLANScan() }
            } label: {
                HStack {
                    Label("Scanner le réseau local (mDNS)", systemImage: "bonjour")
                    Spacer()
                    if viewModel.isLoadingDiscoveryLAN {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(viewModel.isLoadingDiscoveryLAN)

            ForEach(combinedLANDiscoveryItems.filter { !$0.isPairingReceiver }) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(item.serviceType) • \(item.host):\(item.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("+ Ajouter") {
                        addServiceFromDiscovery(item)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Découverte LAN (_http, _ssh, _smb)")
        }

        Section {
            TextField("IP / Hôte par défaut pour les modèles", text: $templateHostInput)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

            ForEach(HomelabTemplate.presets) { template in
                HStack(spacing: 10) {
                    ServiceIconView(
                        icon: template.icon,
                        serviceId: template.id,
                        serviceName: template.name,
                        isOnline: true,
                        size: 32
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(template.description) (:\(template.defaultPort))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("+ Ajouter") {
                        addServiceFromTemplate(template)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Modèles Homelab rapides")
        }

        Section("Ajout manuel rapide") {
            DisclosureGroup("Créer un service personnalisé", isExpanded: $showManualServiceForm) {
                TextField("Nom du service", text: $manualSvcName)
                Picker("Protocole", selection: $manualSvcProtocol) {
                    ForEach(CustomServiceProtocol.allCases) { proto in
                        Label(proto.title, systemImage: proto.systemImage).tag(proto)
                    }
                }
                if manualSvcProtocol == .httpRest || manualSvcProtocol == .jsonMetrics {
                    TextField("URL (ex: http://192.168.1.50:8080)", text: $manualSvcURL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                } else {
                    TextField("Hôte / IP", text: $manualSvcHost)
                        .autocorrectionDisabled()
                    if manualSvcProtocol == .tcpPort {
                        TextField("Port TCP", text: $manualSvcPortText)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }
                Toggle("Activer les alertes", isOn: $manualSvcAlertsEnabled)
                Button("Ajouter à la liste") {
                    addManualService()
                }
                .disabled(manualSvcName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }

        Section("Services prêts à enregistrer (\(stagedServices.count))") {
            if stagedServices.isEmpty {
                Text("Aucun service ajouté pour l'instant (vous pourrez aussi en ajouter plus tard dans l'onglet Services).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stagedServices) { svc in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(svc.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(svc.`protocol`.title) • \(svc.url ?? "\(svc.host ?? ""):\(svc.port ?? 0)")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await testStagedService(svc) }
                            } label: {
                                if testingServiceID == svc.id {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Tester la connexion")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(testingServiceID != nil)

                            Button(role: .destructive) {
                                stagedServices.removeAll { $0.id == svc.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }

                        if let testRes = serviceTestResults[svc.id] {
                            Label(
                                "\(testRes.message) (\(testRes.latencyMs) ms)",
                                systemImage: testRes.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .font(.caption2)
                            .foregroundStyle(testRes.ok ? .green : .red)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: - Step 4: Finalisation (Form Sections)

    @ViewBuilder
    private var step4FinalizeSections: some View {
        Section("Récapitulatif de la configuration") {
            LabeledContent("Nom du profil", value: resolvedServerName)
            LabeledContent("Adresse du serveur", value: normalizedServerURL.isEmpty ? "Non définie" : normalizedServerURL)
            LabeledContent("Authentification", value: authSummaryLabel)
            LabeledContent("Trousseau (Keychain)", value: effectiveBearerToken != nil ? "Jeton prêt à enregistrer" : "Tailscale SSO / Sans jeton")
            LabeledContent("Services ajoutés", value: "\(stagedServices.count)")
            LabeledContent("Notifications Apple", value: pushStatusLabel)
        }

        if let finalizeError {
            Section {
                Label(finalizeError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        Section {
            Button {
                Task { await finishOnboarding() }
            } label: {
                HStack {
                    Spacer()
                    if isFinalizing {
                        ProgressView()
                    } else {
                        Label("Enregistrer & Accéder au tableau de bord", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                    }
                    Spacer()
                }
            }
            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true, cornerRadius: 12)
            .disabled(isFinalizing || normalizedServerURL.isEmpty)

            Button {
                Task { await enterDemoMode() }
            } label: {
                HStack {
                    Spacer()
                    Label("Explorer en Mode Démo", systemImage: "sparkles")
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .tint(.indigo)
        }
    }
    #endif

    // MARK: - tvOS Dedicated Step Cards

    #if os(tvOS)
    private var step1ConnectionTVOS: some View {
        HStack(alignment: .top, spacing: 28) {
            GlassCard(padding: 24, cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Appairage recommandé sur Apple TV", systemImage: "iphone.and.arrow.forward")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DesignTokens.accent(accentTheme, colorScheme))
                    Text("Transférez l'adresse et le jeton depuis votre iPhone sans saisir d'URL avec la télécommande.")
                        .font(.callout)
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))

                    Button {
                        showAppleTVPairing = true
                    } label: {
                        Label("Recevoir depuis iPhone (PIN 6 chiffres)", systemImage: "appletv.fill")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true, cornerRadius: 16)

                    Divider()

                    Text("Serveurs Bonjour (_pvecenter._tcp)")
                        .font(.headline)
                    if viewModel.discoveryService.pveServers.isEmpty {
                        Text("Recherche sur le réseau local…")
                            .font(.callout)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    } else {
                        ForEach(viewModel.discoveryService.pveServers) { srv in
                            bonjourServerRow(srv)
                        }
                    }
                    Button {
                        viewModel.discoveryService.startPVEDiscovery()
                    } label: {
                        Label("Actualiser Bonjour", systemImage: "arrow.clockwise")
                            .font(.callout.weight(.semibold))
                    }
                    .adaptivePillButtonStyle()
                }
            }
            .frame(maxWidth: .infinity)

            GlassCard(padding: 24, cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Connexion manuelle")
                        .font(.title3.weight(.bold))
                    TextField("Nom du serveur", text: $serverNameInput)
                    TextField("https://pve-panel.votre-tailnet.ts.net", text: $serverURLInput)
                    let probeDisabled = isTestingConnection || normalizedServerURL.isEmpty
                    Button {
                        guard !probeDisabled else { return }
                        Task { await testStep1Connection() }
                    } label: {
                        Label(isTestingConnection ? "Test…" : "Tester la connexion", systemImage: "checkmark.shield")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .opacity(probeDisabled ? 0.5 : 1.0)
                    }
                    .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), cornerRadius: 16)

                    if let msg = connectionProbeMessage {
                        Label(msg, systemImage: connectionProbeOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(connectionProbeOK ? .green : .red)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var step2SecurityTVOS: some View {
        GlassCard(padding: 24, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sécurité & Jeton API")
                    .font(.title3.weight(.bold))
                Toggle("Initialiser un nouveau serveur", isOn: $initializeNewServer)
                if initializeNewServer {
                    TextField("Nom du jeton", text: $tokenNameInput)
                    SecureField("Code PIN Admin (optionnel)", text: $adminPinInput)
                    Toggle("Activer Tailscale SSO", isOn: $tailscaleSSOEnabled)
                    Button {
                        Task { await runOnboardingInit() }
                    } label: {
                        Label("Générer le jeton administrateur", systemImage: "key.fill")
                            .font(.callout.weight(.semibold))
                    }
                    .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)

                    if let generated = generatedOneTimeToken {
                        Text("Jeton généré (affiché une seule fois) : \(generated)")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(DesignTokens.nominal(colorScheme))
                    }
                } else {
                    SecureField("Code PIN Admin ou Jeton Bearer", text: $adminPinInput)
                    Button {
                        Task { await signInWithPIN() }
                    } label: {
                        Label("Se connecter via Code PIN", systemImage: "lock.open.fill")
                            .font(.callout.weight(.semibold))
                    }
                    .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                }
                if let msg = authVerifiedMessage {
                    Label(msg, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                if let err = authErrorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
        }
    }

    private var step3ServicesTVOS: some View {
        GlassCard(padding: 24, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Text("Services & Notifications")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Button {
                        Task { await runCombinedLANScan() }
                    } label: {
                        Label("Scanner LAN", systemImage: "dot.radiowaves.left.and.right")
                            .font(.callout.weight(.semibold))
                    }
                    .adaptivePillButtonStyle()

                    Button {
                        Task {
                            let granted = await viewModel.requestPushAuthorization()
                            pushNotificationsOptIn = granted
                        }
                    } label: {
                        Label("Activer alertes", systemImage: "bell.badge.fill")
                            .font(.callout.weight(.semibold))
                    }
                    .adaptivePillButtonStyle(tint: pushNotificationsOptIn ? DesignTokens.nominal(colorScheme) : nil, prominent: pushNotificationsOptIn)
                }
                Text("Modèles rapides : IP \(templateHostInput)")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(HomelabTemplate.presets) { template in
                        Button {
                            addServiceFromTemplate(template)
                        } label: {
                            HStack(spacing: 12) {
                                ServiceIconView(
                                    icon: template.icon,
                                    serviceId: template.id,
                                    serviceName: template.name,
                                    widget: nil,
                                    isOnline: true,
                                    size: 32
                                )
                                Text("+ \(template.name)")
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .adaptivePillButtonStyle(cornerRadius: 14)
                    }
                }
                Text("Services ajoutés : \(stagedServices.count)")
                    .font(.headline)
            }
        }
    }

    private var step4FinalizeTVOS: some View {
        GlassCard(padding: 24, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Prêt à démarrer")
                    .font(.title2.weight(.bold))
                Text("Serveur : \(resolvedServerName) (\(normalizedServerURL))")
                Text("Mode : \(authSummaryLabel) • Services ajoutés : \(stagedServices.count)")
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                if let finalizeError {
                    Label(finalizeError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }
    #endif

    // MARK: - Shared Subviews

    private func bonjourServerRow(_ server: DiscoveryServerItem) -> some View {
        let targetURL = server.resolvedBaseUrl
        let isSelected = !targetURL.isEmpty && targetURL.caseInsensitiveCompare(normalizedServerURL) == .orderedSame
        return Button {
            serverURLInput = targetURL
            serverNameInput = server.name
            if let host = URL(string: targetURL)?.host, !host.isEmpty {
                templateHostInput = host
            }
            Task { await testStep1Connection() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "server.rack")
                    .foregroundStyle(isSelected ? .green : DesignTokens.accent(accentTheme, colorScheme))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(server.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let version = server.version {
                            Text("v\(version)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(targetURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("Choisir")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent(accentTheme, colorScheme))
            }
            #if os(tvOS)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            #endif
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        .cardButtonStyle(cornerRadius: 12)
        #else
        .buttonStyle(.plain)
        #endif
    }

    #if !os(tvOS)
    @ViewBuilder
    private func oneTimeTokenDisplaySection(_ token: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Jeton API généré (affiché une seule fois)", systemImage: "key.viewfinder")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)

                Text(token)
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("Copiez-le en lieu sûr maintenant. Il sera enregistré automatiquement dans votre Trousseau Apple à la finalisation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                #if os(iOS) || os(macOS)
                Button {
                    copyTokenToClipboard(token)
                } label: {
                    Label(tokenCopied ? "Jeton copié !" : "Copier le jeton", systemImage: tokenCopied ? "checkmark.circle.fill" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                #endif
            }
            .padding(.vertical, 4)
        }
    }
    #endif

    // MARK: - Computed Labels

    private var authSummaryLabel: String {
        if generatedOneTimeToken != nil { return "Nouveau jeton API (Initialisation)" }
        switch authChoice {
        case .tailscaleSSO: return "Tailscale SSO"
        case .bearerToken: return "Jeton Bearer"
        case .adminPIN: return "Session PIN Admin"
        }
    }

    private var pushStatusLabel: String {
        switch viewModel.pushManager.authorizationStatus {
        case .authorized: return "Autorisées"
        case .provisional: return "Provisoires"
        #if os(iOS)
        case .ephemeral: return "Éphémères"
        #endif
        case .denied: return "Refusées"
        case .notDetermined: return "Non configurées"
        @unknown default: return "Inconnu"
        }
    }

    private func sfSymbolForTemplate(_ icon: String) -> String {
        switch icon {
        case "film": return "play.tv.fill"
        case "shield": return "lock.shield.fill"
        case "house": return "house.fill"
        case "chart.bar.doc.horizontal": return "chart.bar.doc.horizontal"
        default: return "server.rack"
        }
    }

    // MARK: - Logic & Network Actions

    private func advanceStep() {
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }

    private func applyScannedConnection(_ scanned: QRScannedConnection) {
        serverURLInput = scanned.baseURL
        if serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scanned.serverName != "Serveur" {
            serverNameInput = scanned.serverName
        }
        if let token = scanned.token, !token.isEmpty {
            bearerTokenInput = token
            authChoice = .bearerToken
            initializeNewServer = false
        }
        if let host = URL(string: scanned.baseURL)?.host, !host.isEmpty {
            templateHostInput = host
        }
        Task { await testStep1Connection() }
    }

    private func testStep1Connection() async {
        let target = normalizedServerURL
        guard !target.isEmpty else { return }
        isTestingConnection = true
        connectionProbeMessage = nil

        if let host = URL(string: target)?.host, !host.isEmpty {
            templateHostInput = host
        }

        do {
            let healthy = try await viewModel.apiClient.checkHealth(baseURL: target)
            let status = try await viewModel.checkOnboardingStatus(candidateURL: target)
            onboardingStatus = status
            if serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let remoteName = status.serverName, !remoteName.isEmpty {
                serverNameInput = remoteName
            }
            initializeNewServer = !status.isConfigured
            tailscaleSSOEnabled = status.tailscaleSsoEnabled
            connectionProbeOK = healthy
            connectionProbeMessage = status.isConfigured
                ? "Serveur joignable (« \(status.serverName ?? resolvedServerName) » — déjà configuré)."
                : "Serveur joignable — prêt pour l'initialisation."
        } catch {
            // Fallback to /api/me check when /api/health or /api/onboarding/status requires auth or older server.
            do {
                let user = try await viewModel.testConnection(candidateURL: target, bearerToken: effectiveBearerToken)
                connectionProbeOK = true
                initializeNewServer = false
                connectionProbeMessage = "Serveur joignable (connecté en tant que \(user.login))."
            } catch {
                connectionProbeOK = false
                connectionProbeMessage = error.localizedDescription
            }
        }
        isTestingConnection = false
    }

    private func runOnboardingInit() async {
        let target = normalizedServerURL
        guard !target.isEmpty else { return }
        isAuthenticating = true
        authErrorMessage = nil
        authVerifiedMessage = nil

        let trimmedPin = adminPinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let req = OnboardingInitRequest(
            serverName: resolvedServerName,
            publicUrl: target,
            tokenName: tokenNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.defaultTokenLabel()
                : tokenNameInput.trimmingCharacters(in: .whitespacesAndNewlines),
            adminPin: trimmedPin.isEmpty ? nil : trimmedPin,
            tailscaleSsoEnabled: tailscaleSSOEnabled,
            allowedTailscaleUsers: allowedTailscaleUsers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : allowedTailscaleUsers.trimmingCharacters(in: .whitespacesAndNewlines),
            mdnsEnabled: true,
            pveHost: nonEmpty(optionalPveHost),
            pveNode: nonEmpty(optionalPveNode),
            pveTokenId: nonEmpty(optionalPveTokenId),
            pveTokenSecret: nonEmpty(optionalPveTokenSecret),
            pveVerifySsl: false
        )

        do {
            let response = try await viewModel.apiClient.initOnboarding(
                baseURL: target,
                bearerToken: nil,
                demoMode: viewModel.isDemoMode,
                payload: req
            )
            if let token = response.apiToken, !token.isEmpty {
                generatedOneTimeToken = token
                bearerTokenInput = token
                await viewModel.apiClient.setBearerToken(token)
                // Persist an onboarding secret backup immediately so token is safe in Keychain.
                try? viewModel.keychainStore.saveSecret(token, kind: .onboardingToken, profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            }
            authVerifiedMessage = response.message ?? "Jeton administrateur créé."
        } catch {
            authErrorMessage = error.localizedDescription
        }
        isAuthenticating = false
    }

    private func verifyExistingBearerToken() async {
        let target = normalizedServerURL
        let token = bearerTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !token.isEmpty else { return }
        isAuthenticating = true
        authErrorMessage = nil
        authVerifiedMessage = nil

        do {
            let user = try await viewModel.testConnection(candidateURL: target, bearerToken: token)
            await viewModel.apiClient.setBearerToken(token)
            authVerifiedMessage = "Jeton validé (\(user.login))."
        } catch {
            authErrorMessage = error.localizedDescription
        }
        isAuthenticating = false
    }

    private func signInWithPIN() async {
        let target = normalizedServerURL
        let pin = adminPinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !pin.isEmpty else { return }
        isAuthenticating = true
        authErrorMessage = nil
        authVerifiedMessage = nil

        do {
            let resp = try await viewModel.apiClient.login(
                baseURL: target,
                demoMode: viewModel.isDemoMode,
                payload: AuthLoginRequest(pin: pin, deviceName: Self.defaultTokenLabel())
            )
            if !resp.token.isEmpty {
                bearerTokenInput = resp.token
                await viewModel.apiClient.setBearerToken(resp.token)
            }
            authVerifiedMessage = "Session ouverte (\(resp.user?.login ?? "Admin"))."
        } catch {
            authErrorMessage = error.localizedDescription
        }
        isAuthenticating = false
    }

    private func verifyTailscaleSSO() async {
        let target = normalizedServerURL
        guard !target.isEmpty else { return }
        isAuthenticating = true
        authErrorMessage = nil
        authVerifiedMessage = nil

        do {
            let user = try await viewModel.testConnection(candidateURL: target, bearerToken: nil)
            tailscaleSSOEnabled = true
            authVerifiedMessage = "Identité Tailscale vérifiée : \(user.login)."
        } catch {
            authErrorMessage = error.localizedDescription
        }
        isAuthenticating = false
    }

    private func runCombinedLANScan() async {
        await viewModel.scanLANAndServerDiscovery()
        if !normalizedServerURL.isEmpty {
            await viewModel.apiClient.setBearerToken(effectiveBearerToken)
            if let serverSide = try? await viewModel.apiClient.fetchLANDiscovery(
                baseURL: normalizedServerURL,
                demoMode: viewModel.isDemoMode
            ) {
                extraServerLANDiscovery = serverSide
            }
        }
    }

    private func addServiceFromDiscovery(_ item: DiscoveryServerItem) {
        let resolvedURL = item.resolvedBaseUrl
        let proto = item.suggestedProtocol ?? .httpRest
        let newService = CustomServiceConfig(
            id: "svc-\(UUID().uuidString.prefix(8).lowercased())",
            name: item.name,
            description: "Découvert sur le réseau local (\(item.serviceType))",
            category: "Réseau local",
            icon: proto == .tcpPort ? "terminal" : "server",
            protocol: proto,
            host: item.host,
            port: item.port,
            url: (proto == .httpRest || proto == .jsonMetrics) ? resolvedURL : nil,
            healthUrl: (proto == .httpRest || proto == .jsonMetrics) ? resolvedURL : nil,
            order: stagedServices.count,
            enabled: true
        )
        if !stagedServices.contains(where: { $0.name == newService.name && $0.port == newService.port }) {
            stagedServices.append(newService)
        }
    }

    private func addServiceFromTemplate(_ template: HomelabTemplate) {
        let host = templateHostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "192.168.1.10"
            : templateHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = template.useHttps ? "https" : "http"
        let base = "\(scheme)://\(host):\(template.defaultPort)"
        let health = template.defaultPath.isEmpty ? base : "\(base)\(template.defaultPath)"
        let newService = CustomServiceConfig(
            id: "\(template.id)-\(UUID().uuidString.prefix(4).lowercased())",
            name: template.name,
            description: template.description,
            category: template.category,
            icon: template.icon,
            protocol: template.protocol,
            host: host,
            port: template.defaultPort,
            url: base,
            healthUrl: health,
            verifySsl: !template.useHttps,
            order: stagedServices.count,
            enabled: true
        )
        stagedServices.append(newService)
    }

    private func addManualService() {
        let name = manualSvcName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let port = Int(manualSvcPortText.trimmingCharacters(in: .whitespacesAndNewlines))
        let newService = CustomServiceConfig(
            id: "svc-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            description: "Ajouté lors de l'installation",
            category: "Services",
            icon: manualSvcProtocol == .tcpPort ? "network" : "server",
            protocol: manualSvcProtocol,
            host: nonEmpty(manualSvcHost),
            port: port,
            url: nonEmpty(manualSvcURL),
            healthUrl: nonEmpty(manualSvcURL),
            order: stagedServices.count,
            enabled: true,
            alertPolicy: AlertPolicyConfig(enabled: manualSvcAlertsEnabled)
        )
        stagedServices.append(newService)
        manualSvcName = ""
        manualSvcURL = ""
        manualSvcHost = ""
        showManualServiceForm = false
    }

    private func testStagedService(_ svc: CustomServiceConfig) async {
        testingServiceID = svc.id
        let target = normalizedServerURL
        await viewModel.apiClient.setBearerToken(effectiveBearerToken)
        if !target.isEmpty || viewModel.isDemoMode {
            do {
                let res = try await viewModel.apiClient.testCustomService(
                    baseURL: target,
                    demoMode: viewModel.isDemoMode,
                    serviceId: svc.id,
                    override: svc
                )
                serviceTestResults[svc.id] = res
            } catch {
                serviceTestResults[svc.id] = CustomServiceTestResult(
                    ok: false,
                    status: "down",
                    latencyMs: 0,
                    message: error.localizedDescription
                )
            }
        } else {
            serviceTestResults[svc.id] = CustomServiceTestResult(
                ok: false,
                status: "error",
                latencyMs: 0,
                message: "Définissez l'adresse du serveur à l'étape 1 pour tester."
            )
        }
        testingServiceID = nil
    }

    private func finishOnboarding() async {
        let target = normalizedServerURL
        guard !target.isEmpty else { return }
        isFinalizing = true
        finalizeError = nil

        let token = effectiveBearerToken
        await viewModel.apiClient.setBearerToken(token)

        for service in stagedServices {
            _ = try? await viewModel.apiClient.createCustomService(
                baseURL: target,
                demoMode: viewModel.isDemoMode,
                service: service
            )
        }

        let usesTailscale = (authChoice == .tailscaleSSO || tailscaleSSOEnabled) && (token == nil)
        await viewModel.completeOnboarding(
            serverName: resolvedServerName,
            baseURL: target,
            bearerToken: token,
            usesTailscaleSSO: usesTailscale
        )
        isFinalizing = false
        dismiss()
    }

    private func enterDemoMode() async {
        await viewModel.configureConnection(baseURL: "", demoMode: true)
        viewModel.dismissOnboarding()
        dismiss()
    }

    #if os(iOS) || os(macOS)
    private func copyTokenToClipboard(_ token: String) {
        #if os(iOS)
        UIPasteboard.general.string = token
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        #endif
        tokenCopied = true
    }
    #endif

    private func nonEmpty(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func defaultTokenLabel() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "PVE Center Mac"
        #elseif os(tvOS)
        return "Apple TV"
        #else
        return UIDevice.current.name
        #endif
    }
}
