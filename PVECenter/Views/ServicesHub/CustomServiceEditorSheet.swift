import SwiftUI

public enum ServiceSymbolCatalog: Sendable {
    public struct SymbolOption: Identifiable, Hashable, Sendable {
        public let id: String
        public let label: String
        public let symbol: String

        public init(_ id: String, label: String, symbol: String) {
            self.id = id
            self.label = label
            self.symbol = symbol
        }
    }

    public static let options: [SymbolOption] = [
        SymbolOption("server.rack", label: "Serveur", symbol: "server.rack"),
        SymbolOption("globe", label: "Web", symbol: "globe"),
        SymbolOption("play.tv.fill", label: "Médias", symbol: "play.tv.fill"),
        SymbolOption("lock.shield.fill", label: "Sécurité", symbol: "lock.shield.fill"),
        SymbolOption("terminal.fill", label: "SSH", symbol: "terminal.fill"),
        SymbolOption("wifi", label: "Réseau", symbol: "wifi"),
        SymbolOption("network", label: "Port TCP", symbol: "network"),
        SymbolOption("chart.bar.doc.horizontal", label: "Métriques", symbol: "chart.bar.doc.horizontal"),
        SymbolOption("externaldrive.badge.checkmark", label: "Backup", symbol: "externaldrive.badge.checkmark"),
        SymbolOption("cylinder.split.1x2.fill", label: "Base", symbol: "cylinder.split.1x2.fill"),
        SymbolOption("house.fill", label: "Domotique", symbol: "house.fill"),
        SymbolOption("arrow.down.circle.fill", label: "Transfert", symbol: "arrow.down.circle.fill"),
        SymbolOption("tray.and.arrow.down.fill", label: "Webhook", symbol: "tray.and.arrow.down.fill"),
        SymbolOption("cpu", label: "Compute", symbol: "cpu"),
    ]

    public static func resolveSFSymbol(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "", "server": return "server.rack"
        case "film", "tv": return "play.tv.fill"
        case "clapperboard": return "film.stack.fill"
        case "sparkles": return "sparkles"
        case "search": return "magnifyingglass.circle.fill"
        case "download": return "arrow.down.circle.fill"
        case "shield": return "lock.shield.fill"
        case "database": return "cylinder.split.1x2.fill"
        case "terminal": return "terminal.fill"
        case "wifi": return "wifi"
        case "globe": return "globe"
        case "network": return "network"
        default: return trimmed
        }
    }

    public static func shortProtocolBadge(_ proto: CustomServiceProtocol) -> String {
        switch proto {
        case .httpRest: "HTTP"
        case .tcpPort: "TCP"
        case .icmpPing: "ICMP"
        case .jsonMetrics: "Metrics"
        case .webhookIngest: "Webhook"
        }
    }

    public static func shortProtocolBadge(raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let parsed = CustomServiceProtocol(rawValue: raw.lowercased()) {
            return shortProtocolBadge(parsed)
        }
        switch raw.lowercased() {
        case "http", "https", "rest": return "HTTP"
        case "tcp": return "TCP"
        case "icmp", "ping": return "ICMP"
        case "metrics", "json": return "Metrics"
        case "webhook": return "Webhook"
        default: return raw.uppercased()
        }
    }
}

public struct CustomServiceEditorSheet: View {
    public var viewModel: AppViewModel
    public let existingService: CustomServiceConfig?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var name: String
    @State private var description: String
    @State private var category: String
    @State private var icon: String
    @State private var selectedProtocol: CustomServiceProtocol
    @State private var host: String
    @State private var portText: String
    @State private var url: String
    @State private var healthUrl: String
    @State private var internalUrl: String
    @State private var authType: CustomServiceAuthType
    @State private var authHeaderName: String
    @State private var authToken: String
    @State private var jsonMetricPath: String
    @State private var expectedStatus: Int
    @State private var refreshIntervalSeconds: Int
    @State private var verifySsl: Bool
    @State private var webhookTtlSeconds: Int
    @State private var enabled: Bool

    @State private var alertEnabled: Bool
    @State private var consecutiveFailures: Int
    @State private var cooldownSeconds: Int

    @State private var isTesting: Bool = false
    @State private var testResult: CustomServiceTestResult?
    @State private var isSaving: Bool = false

    private let categorySuggestions = [
        "Services",
        "Médias & Streaming",
        "Téléchargements & Automation",
        "Infrastructure & Sécurité",
        "Réseau & Domotique",
    ]

    public init(viewModel: AppViewModel, existingService: CustomServiceConfig? = nil) {
        self.viewModel = viewModel
        self.existingService = existingService

        _name = State(initialValue: existingService?.name ?? "")
        _description = State(initialValue: existingService?.description ?? "")
        _category = State(initialValue: existingService?.category ?? "Services")
        _icon = State(initialValue: existingService?.icon ?? "server.rack")
        _selectedProtocol = State(initialValue: existingService?.`protocol` ?? .httpRest)
        _host = State(initialValue: existingService?.host ?? "")
        _portText = State(initialValue: existingService?.port.map(String.init) ?? "")
        _url = State(initialValue: existingService?.url ?? "")
        _healthUrl = State(initialValue: existingService?.healthUrl ?? "")
        _internalUrl = State(initialValue: existingService?.internalUrl ?? "")
        _authType = State(initialValue: existingService?.authType ?? .none)
        _authHeaderName = State(initialValue: existingService?.authHeaderName ?? "X-API-Key")
        _authToken = State(initialValue: existingService?.authToken ?? "")
        _jsonMetricPath = State(initialValue: existingService?.jsonMetricPath ?? "")
        _expectedStatus = State(initialValue: existingService?.expectedStatus ?? 200)
        _refreshIntervalSeconds = State(initialValue: existingService?.refreshIntervalSeconds ?? 30)
        _verifySsl = State(initialValue: existingService?.verifySsl ?? true)
        _webhookTtlSeconds = State(initialValue: existingService?.webhookTtlSeconds ?? 300)
        _enabled = State(initialValue: existingService?.enabled ?? true)

        _alertEnabled = State(initialValue: existingService?.alertPolicy.enabled ?? true)
        _consecutiveFailures = State(initialValue: existingService?.alertPolicy.consecutiveFailures ?? 3)
        _cooldownSeconds = State(initialValue: existingService?.alertPolicy.cooldownSeconds ?? 300)
    }

    private var isEditing: Bool { existingService != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        guard !trimmedName.isEmpty else { return false }
        switch selectedProtocol {
        case .httpRest, .jsonMetrics:
            return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !healthUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .tcpPort:
            let hasHost = !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let portVal = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return hasHost && (1...65535).contains(portVal)
        case .icmpPing:
            return !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .webhookIngest:
            return true
        }
    }

    public var body: some View {
        NavigationStack {
            #if os(tvOS)
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isEditing ? "Modifier \(trimmedName.isEmpty ? "le service" : trimmedName)" : "Nouveau service")
                                    .font(.largeTitle.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .lineLimit(1)
                                Text("Sonde, protocole, icône et politique d'alerte")
                                    .font(.callout)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                            Spacer()
                            Button("Annuler") { dismiss() }
                                .adaptivePillButtonStyle()
                            Button {
                                guard canSubmit && !isSaving else { return }
                                Task { await saveService() }
                            } label: {
                                Text(isSaving ? "Enregistrement…" : (isEditing ? "Enregistrer" : "Ajouter"))
                                    .opacity(canSubmit && !isSaving ? 1.0 : 0.45)
                            }
                            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                        }
                        .focusSection()

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Identité")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                identityFields
                            }
                        }

                        iconPickerSection

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Protocole & Cible")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                protocolTargetFields
                            }
                        }

                        if supportsAuth {
                            GlassCard(padding: 24, cornerRadius: 22) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Authentification")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    authFields
                                }
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Politique d'alerte")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                alertPolicyFields
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Diagnostic préalable")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                liveTestFields
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            #else
            Form {
                Section("Identité") { identityFields }
                iconPickerSection
                Section("Protocole & Cible") { protocolTargetFields }
                if supportsAuth {
                    Section("Authentification") { authFields }
                }
                Section("Politique d'alerte") { alertPolicyFields }
                Section("Diagnostic préalable") { liveTestFields }
            }
            .adaptiveTVOSModalFormContainer()
            .navigationTitle(isEditing ? "Modifier le service" : "Nouveau service")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Enregistrement…" : (isEditing ? "Enregistrer" : "Ajouter")) {
                        Task { await saveService() }
                    }
                    .disabled(!canSubmit || isSaving)
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 620)
        #endif
    }

    private var supportsAuth: Bool {
        switch selectedProtocol {
        case .httpRest, .jsonMetrics, .webhookIngest:
            return true
        case .tcpPort, .icmpPing:
            return false
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var identityFields: some View {
        TextField("Nom du service (ex: Jellyfin, Vaultwarden)", text: $name)
        TextField("Description (optionnelle)", text: $description)

        TextField("Catégorie", text: $category)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categorySuggestions, id: \.self) { suggestion in
                    let selected = category == suggestion
                    Button(suggestion) {
                        category = suggestion
                    }
                    .adaptivePillButtonStyle(
                        tint: selected ? DesignTokens.accent(accentTheme, colorScheme) : nil,
                        prominent: selected
                    )
                    .adaptiveSmallControlSize()
                }
            }
            .padding(.vertical, 4)
        }

        Toggle("Supervision active", isOn: $enabled)
    }

    private var iconPickerSection: some View {
        ServiceIconPickerSection(
            selectedIcon: $icon,
            serviceId: existingService?.id,
            serviceName: name,
            widget: nil
        )
    }

    @ViewBuilder
    private var protocolTargetFields: some View {
        Picker("Protocole", selection: $selectedProtocol) {
            ForEach(CustomServiceProtocol.allCases) { proto in
                Label(proto.title, systemImage: proto.systemImage).tag(proto)
            }
        }

        switch selectedProtocol {
        case .httpRest, .jsonMetrics:
            TextField("URL principale (https://…)", text: $url)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            TextField("URL de healthcheck (optionnelle)", text: $healthUrl)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            TextField("URL interne LAN (optionnelle)", text: $internalUrl)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif

            if selectedProtocol == .jsonMetrics {
                TextField("Chemin JSON métriques (ex: data.streams ou *) ", text: $jsonMetricPath)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            httpExpectedStatusControl
            Toggle("Vérifier le certificat SSL", isOn: $verifySsl)

        case .tcpPort:
            TextField("Hôte ou IP (ex: 192.168.1.10)", text: $host)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            TextField("Port TCP (ex: 22, 443, 5432)", text: $portText)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            TextField("URL web associée (optionnelle)", text: $url)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif

        case .icmpPing:
            TextField("Hôte ou IP (ex: 192.168.1.1)", text: $host)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            TextField("URL web associée (optionnelle)", text: $url)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif

        case .webhookIngest:
            Picker("Expiration TTL du heartbeat", selection: $webhookTtlSeconds) {
                Text("5 minutes").tag(300)
                Text("1 heure").tag(3600)
                Text("6 heures").tag(21600)
                Text("24 heures").tag(86400)
            }
            Text("Endpoint d'ingestion : POST /api/custom-services/\(existingService?.id ?? "<id>")/webhook")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }

        Picker("Intervalle de vérification", selection: $refreshIntervalSeconds) {
            Text("10 secondes").tag(10)
            Text("30 secondes").tag(30)
            Text("1 minute").tag(60)
            Text("5 minutes").tag(300)
        }
    }

    @ViewBuilder
    private var httpExpectedStatusControl: some View {
        #if os(tvOS)
        Picker("Statut HTTP attendu", selection: $expectedStatus) {
            Text("200 OK").tag(200)
            Text("204 No Content").tag(204)
            Text("301 / 302 Redirect").tag(302)
            Text("401 Auth Required").tag(401)
        }
        #else
        Stepper("Code HTTP attendu : \(expectedStatus)", value: $expectedStatus, in: 100...599)
        #endif
    }

    @ViewBuilder
    private var authFields: some View {
        Picker("Type d'authentification", selection: $authType) {
            ForEach(CustomServiceAuthType.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }

        if authType == .header {
            TextField("Nom de l'en-tête HTTP", text: $authHeaderName)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }

        if authType != .none {
            SecureField(
                existingService?.authTokenSet == true
                    ? "Jeton / Secret (laisser vide pour conserver)"
                    : "Jeton / Mot de passe / Clé API",
                text: $authToken
            )
        }
    }

    @ViewBuilder
    private var alertPolicyFields: some View {
        Toggle("Alerter en cas d'indisponibilité", isOn: $alertEnabled)

        if alertEnabled {
            #if os(tvOS)
            HStack {
                Text("Échecs consécutifs : \(consecutiveFailures)")
                Spacer()
                Button {
                    if consecutiveFailures > 1 { consecutiveFailures -= 1 }
                } label: {
                    Image(systemName: "minus")
                }
                .adaptivePillButtonStyle()
                Button {
                    if consecutiveFailures < 10 { consecutiveFailures += 1 }
                } label: {
                    Image(systemName: "plus")
                }
                .adaptivePillButtonStyle()
            }
            #else
            Stepper(
                "Échecs consécutifs avant alerte : \(consecutiveFailures)",
                value: $consecutiveFailures,
                in: 1...10
            )
            #endif

            Picker("Refroidissement entre alertes", selection: $cooldownSeconds) {
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
                Text("15 minutes").tag(900)
                Text("1 heure").tag(3600)
            }
        }
    }

    @ViewBuilder
    private var liveTestFields: some View {
        Button {
            guard canSubmit && !isTesting else { return }
            Task { await runLiveTest() }
        } label: {
            HStack {
                if isTesting {
                    ProgressView()
                        .adaptiveSmallControlSize()
                } else {
                    Image(systemName: "bolt.horizontal.circle.fill")
                }
                Text(isTesting ? "Test en cours…" : "Tester la connexion")
                    .fontWeight(.semibold)
            }
            .opacity(canSubmit && !isTesting ? 1.0 : 0.5)
        }
        #if os(tvOS)
        .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme))
        #else
        .disabled(!canSubmit || isTesting)
        #endif

        if let result = testResult {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(result.ok ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme))
                    Text(result.message)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(result.latencyMs) ms")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let httpStatus = result.httpStatus {
                    Text("Statut HTTP : \(httpStatus)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let metrics = result.metrics, !metrics.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(metrics.keys.sorted(), id: \.self) { key in
                                if let val = metrics[key] {
                                    Text("\(key): \(val.displayString)")
                                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            DesignTokens.surfaceElevated(theme: accentTheme, colorScheme),
                                            in: Capsule()
                                        )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private func buildConfig() -> CustomServiceConfig {
        let slugBase = trimmedName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let generatedID = existingService?.id ?? (slugBase.isEmpty ? UUID().uuidString.lowercased() : "\(slugBase)-\(Int(Date().timeIntervalSince1970) % 10000)")

        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHealthURL = healthUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanInternalURL = internalUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHeader = authHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMetricPath = jsonMetricPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedPort = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines))

        return CustomServiceConfig(
            id: generatedID,
            name: trimmedName,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Services" : category.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "server.rack" : icon.trimmingCharacters(in: .whitespacesAndNewlines),
            protocol: selectedProtocol,
            host: cleanHost.isEmpty ? nil : cleanHost,
            port: parsedPort,
            url: cleanURL.isEmpty ? nil : cleanURL,
            healthUrl: cleanHealthURL.isEmpty ? nil : cleanHealthURL,
            internalUrl: cleanInternalURL.isEmpty ? nil : cleanInternalURL,
            authType: supportsAuth ? authType : .none,
            authToken: (supportsAuth && authType != .none && !cleanToken.isEmpty) ? cleanToken : nil,
            authHeaderName: (supportsAuth && authType == .header && !cleanHeader.isEmpty) ? cleanHeader : nil,
            jsonMetricPath: (selectedProtocol == .jsonMetrics && !cleanMetricPath.isEmpty) ? cleanMetricPath : nil,
            expectedStatus: (selectedProtocol == .httpRest || selectedProtocol == .jsonMetrics) ? expectedStatus : nil,
            refreshIntervalSeconds: refreshIntervalSeconds,
            verifySsl: verifySsl,
            webhookTtlSeconds: webhookTtlSeconds,
            order: existingService?.order ?? viewModel.customServices.count,
            enabled: enabled,
            alertPolicy: AlertPolicyConfig(
                enabled: alertEnabled,
                consecutiveFailures: consecutiveFailures,
                cooldownSeconds: cooldownSeconds
            ),
            authTokenSet: existingService?.authTokenSet
        )
    }

    private func runLiveTest() async {
        isTesting = true
        let draft = buildConfig()
        testResult = await viewModel.testCustomService(id: draft.id, override: draft)
        isTesting = false
    }

    private func saveService() async {
        isSaving = true
        let config = buildConfig()
        let ok: Bool
        if let existingService {
            ok = await viewModel.updateCustomService(id: existingService.id, service: config)
        } else {
            ok = await viewModel.createCustomService(config)
        }
        isSaving = false
        if ok {
            dismiss()
        }
    }
}
