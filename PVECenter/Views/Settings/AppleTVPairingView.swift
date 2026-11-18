import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public enum PairingRoleMode: String, CaseIterable, Identifiable, Sendable {
    case receiver
    case sender

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .receiver: "Recevoir (Apple TV)"
        case .sender: "Envoyer (iPhone / Mac)"
        }
    }

    public var systemImage: String {
        switch self {
        case .receiver: "appletv.fill"
        case .sender: "iphone.and.arrow.forward"
        }
    }
}

public struct AppleTVPairingView: View {
    public var viewModel: AppViewModel
    public let onPaired: ((PairingTransferPayload) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var roleMode: PairingRoleMode
    @State private var selectedTargetID: String?
    @State private var pinInput: String = ""
    @State private var customRelayURL: String = ""
    @State private var isSending: Bool = false
    @State private var hasAppliedPayload: Bool = false
    @State private var showRelayField: Bool = false

    public init(
        viewModel: AppViewModel,
        initialMode: PairingRoleMode? = nil,
        onPaired: ((PairingTransferPayload) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onPaired = onPaired
        #if os(tvOS)
        _roleMode = State(initialValue: initialMode ?? .receiver)
        #else
        _roleMode = State(initialValue: initialMode ?? .sender)
        #endif
    }

    private var selectedTarget: DiscoveryServerItem? {
        guard let selectedTargetID else { return nil }
        return viewModel.discoveryService.pairingReceivers.first(where: { $0.id == selectedTargetID })
    }

    private var sanitizedPIN: String {
        String(pinInput.filter(\.isNumber).prefix(6))
    }

    private var resolvedRelayURL: String? {
        let custom = APIClient.normalizeBaseURL(customRelayURL)
        if !custom.isEmpty { return custom }
        if !viewModel.isDemoMode && !viewModel.serverBaseURL.isEmpty {
            return viewModel.serverBaseURL
        }
        return nil
    }

    public var body: some View {
        NavigationStack {
            Group {
                #if os(tvOS)
                tvOSLayout
                #else
                standardLayout
                #endif
            }
            .navigationTitle("Appairage chiffré")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        cleanup()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 540)
        #endif
        #if os(tvOS)
        .preferredColorScheme(.dark)
        #else
        .preferredColorScheme(viewModel.preferredColorScheme)
        #endif
        .task(id: roleMode) {
            await activateCurrentMode()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: viewModel.pairingService.receivedPayload) { _, newPayload in
            guard let payload = newPayload, !hasAppliedPayload else { return }
            hasAppliedPayload = true
            Task {
                await viewModel.applyReceivedPairingPayload(payload)
                onPaired?(payload)
                try? await Task.sleep(for: .seconds(1.0))
                dismiss()
            }
        }
    }

    // MARK: - tvOS 10-Foot Layout

    #if os(tvOS)
    private var tvOSLayout: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .center, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Appairage Apple TV")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            Text("Échange chiffré de bout en bout (ECDH P-256 + HKDF + AES-256-GCM)")
                                .font(.callout)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                        Spacer()
                        AdaptiveSegmentedControl(
                            options: PairingRoleMode.allCases,
                            selection: $roleMode,
                            title: \.title
                        )

                        Button {
                            cleanup()
                            dismiss()
                        } label: {
                            Label("Fermer", systemImage: "xmark.circle.fill")
                                .font(.callout.weight(.semibold))
                        }
                        .adaptivePillButtonStyle()
                    }
                    .focusSection()

                    if roleMode == .receiver {
                        tvOSReceiverCard
                    } else {
                        tvOSSenderCard
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var tvOSReceiverCard: some View {
        HStack(alignment: .top, spacing: 32) {
            GlassCard(padding: 28, cornerRadius: 24) {
                VStack(alignment: .center, spacing: 22) {
                    if let payload = viewModel.pairingService.receivedPayload {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(DesignTokens.nominal(colorScheme))
                        Text("Configuration reçue !")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Text("\(payload.serverName) • \(payload.baseUrl)")
                            .font(.callout)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    } else {
                        Text("CODE PIN D'APPAIRAGE")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(DesignTokens.accent(accentTheme, colorScheme))

                        pinDigitsDisplay(pin: viewModel.pairingService.activePIN ?? "------", large: true)

                        receiverCountdownView

                        if let error = viewModel.pairingService.lastError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(DesignTokens.critical(colorScheme))
                        }

                        Button {
                            Task { await restartReceiver() }
                        } label: {
                            Label("Générer un nouveau code", systemImage: "arrow.clockwise")
                                .font(.callout.weight(.semibold))
                                .frame(minWidth: 280, minHeight: 42)
                        }
                        .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            GlassCard(padding: 28, cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Comment appairer", systemImage: "iphone.gen3")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                    instructionRow(step: "1", text: "Ouvrez PVE Center sur votre iPhone ou Mac")
                    instructionRow(step: "2", text: "Allez dans Paramètres → Appairer une Apple TV")
                    instructionRow(step: "3", text: "Sélectionnez cet appareil et saisissez le code à 6 chiffres")

                    Divider()

                    Button {
                        showRelayField.toggle()
                    } label: {
                        HStack {
                            Label("Relais HTTPS optionnel (VLAN différent)", systemImage: "network")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Image(systemName: showRelayField ? "chevron.up" : "chevron.down")
                        }
                    }
                    .adaptivePillButtonStyle(cornerRadius: 16)

                    if showRelayField {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("https://pve-panel.votre-tailnet.ts.net", text: $customRelayURL)
                                .autocorrectionDisabled()
                            Button("Appliquer le relais") {
                                Task { await restartReceiver() }
                            }
                            .font(.callout.weight(.semibold))
                            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme))
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var tvOSSenderCard: some View {
        GlassCard(padding: 28, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Envoyer la configuration actuelle")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))

                senderTargetList
                TextField("Code PIN à 6 chiffres", text: $pinInput)
                    .autocorrectionDisabled()
                senderStatusBanner
                senderSendButton
            }
        }
    }
    #endif

    // MARK: - iOS / macOS Form Layout

    private var standardLayout: some View {
        Form {
            Section {
                Picker("Rôle de cet appareil", selection: $roleMode) {
                    ForEach(PairingRoleMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if roleMode == .receiver {
                receiverFormSections
            } else {
                senderFormSections
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var receiverFormSections: some View {
        Section {
            if let payload = viewModel.pairingService.receivedPayload {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.green)
                    Text("Configuration reçue et déchiffrée")
                        .font(.headline)
                    Text("\(payload.serverName) (\(payload.baseUrl))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 16) {
                    Text("Ouvrez PVE Center sur votre iPhone -> Paramètres -> Appairer une Apple TV")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    pinDigitsDisplay(pin: viewModel.pairingService.activePIN ?? "------", large: false)

                    receiverCountdownView

                    if let error = viewModel.pairingService.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await restartReceiver() }
                    } label: {
                        Label("Générer un nouveau code", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        } header: {
            Text("Code PIN à 6 chiffres")
        }

        Section("Relais HTTPS (optionnel)") {
            TextField("https://pve-panel.votre-tailnet.ts.net", text: $customRelayURL)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

            Button {
                Task { await restartReceiver() }
            } label: {
                Label("Redémarrer l'écoute", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }

    @ViewBuilder
    private var senderFormSections: some View {
        Section("Configuration à transférer") {
            if viewModel.serverBaseURL.isEmpty && !viewModel.isDemoMode {
                Label("Aucun serveur connecté sur cet appareil. Connectez d'abord un serveur.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                LabeledContent("Serveur", value: viewModel.activeServerName)
                LabeledContent("Adresse", value: viewModel.isDemoMode ? "https://panel.example.ts.net" : viewModel.serverBaseURL)
                LabeledContent("Jeton Trousseau", value: viewModel.hasActiveToken ? "Inclus (chiffré)" : "Non défini / Tailscale SSO")
            }
        }

        Section {
            senderTargetList
        } header: {
            HStack {
                Text("Appareils Apple TV détectés (_pvepair._tcp)")
                Spacer()
                if viewModel.discoveryService.isScanningPairing {
                    ProgressView()
                        .adaptiveSmallControlSize()
                }
            }
        } footer: {
            Text("Si l'Apple TV est sur un autre VLAN ou Tailscale, sélectionnez « Relais HTTPS du serveur ».")
        }

        Section("Code PIN affiché sur l'Apple TV") {
            TextField("Saisir les 6 chiffres", text: $pinInput)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .multilineTextAlignment(.center)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onChange(of: pinInput) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(6))
                    if filtered != newValue {
                        pinInput = filtered
                    }
                }

            pinDigitsDisplay(pin: sanitizedPIN.padding(toLength: 6, withPad: "•", startingAt: 0), large: false)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            senderStatusBanner
            senderSendButton
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var senderTargetList: some View {
        let receivers = viewModel.discoveryService.pairingReceivers

        Button {
            selectedTargetID = nil
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedTargetID == nil ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedTargetID == nil ? DesignTokens.accent(accentTheme, colorScheme) : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Relais HTTPS du serveur")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Fonctionne même à travers Tailscale ou un VLAN différent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .adaptiveIconTileButtonStyle(
            isSelected: selectedTargetID == nil,
            accent: DesignTokens.accent(accentTheme, colorScheme),
            cornerRadius: 12
        )

        if receivers.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                Text("Recherche d'appareils Bonjour en cours…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(receivers) { receiver in
                let isSelected = selectedTargetID == receiver.id
                Button {
                    selectedTargetID = receiver.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "appletv.fill")
                            .foregroundStyle(isSelected ? DesignTokens.accent(accentTheme, colorScheme) : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(receiver.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(receiver.host):\(receiver.port) • Bonjour local")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .adaptiveIconTileButtonStyle(
                    isSelected: isSelected,
                    accent: DesignTokens.accent(accentTheme, colorScheme),
                    cornerRadius: 12
                )
            }
        }
    }

    @ViewBuilder
    private var senderStatusBanner: some View {
        switch viewModel.pairingService.senderState {
        case .idle:
            EmptyView()
        case .connecting:
            Label("Connexion à l'appareil cible…", systemImage: "network")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .encrypting:
            Label("Chiffrement ECDH P-256 + AES-GCM…", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(DesignTokens.accent(accentTheme, colorScheme))
        case .waitingForAck:
            Label("Envoi et attente de confirmation…", systemImage: "paperplane.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .sentSuccess(let targetDevice, let transport):
            Label(
                "Configuration envoyée à « \(targetDevice) » via \(transport.label).",
                systemImage: "checkmark.seal.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private var senderSendButton: some View {
        let canSend = !isSending
            && sanitizedPIN.count == 6
            && (!viewModel.serverBaseURL.isEmpty || viewModel.isDemoMode)

        return Button {
            guard canSend else { return }
            Task { await sendPayload() }
        } label: {
            HStack {
                Spacer()
                if isSending {
                    ProgressView()
                } else {
                    Label("Chiffrer et envoyer", systemImage: "lock.rotation")
                        .font(.headline)
                }
                Spacer()
            }
            #if os(tvOS)
            .frame(minHeight: 46)
            .opacity(canSend ? 1.0 : 0.45)
            #endif
        }
        .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true, cornerRadius: 14)
        #if !os(tvOS)
        .disabled(!canSend)
        #endif
    }

    private func pinDigitsDisplay(pin: String, large: Bool) -> some View {
        let chars = Array(pin.padding(toLength: 6, withPad: "-", startingAt: 0).prefix(6))
        return HStack(spacing: large ? 16 : 8) {
            ForEach(Array(chars.enumerated()), id: \.offset) { index, char in
                if index == 3 {
                    Spacer().frame(width: large ? 12 : 4)
                }
                Text(String(char))
                    .font(.system(size: large ? 54 : 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                    .frame(width: large ? 74 : 42, height: large ? 90 : 52)
                    .background(
                        DesignTokens.surfaceElevated(theme: accentTheme, colorScheme),
                        in: RoundedRectangle(cornerRadius: large ? 18 : 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: large ? 18 : 12, style: .continuous)
                            .strokeBorder(DesignTokens.hairBorder(colorScheme), lineWidth: 1)
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code PIN : \(chars.map(String.init).joined(separator: " "))")
    }

    @ViewBuilder
    private var receiverCountdownView: some View {
        if case .advertising(_, let transport, let expiresAt) = viewModel.pairingService.receiverState {
            VStack(spacing: 6) {
                StatusPill(transport.label, color: DesignTokens.accent(accentTheme, colorScheme), systemImage: "antenna.radiowaves.left.and.right")

                if let expiresAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(expiresAt.timeIntervalSince(context.date)))
                        let mins = remaining / 60
                        let secs = remaining % 60
                        Text(remaining > 0
                             ? String(format: "Expire dans %02d:%02d", mins, secs)
                             : "Code PIN expiré — générez un nouveau code")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(remaining <= 30 ? Color.orange : DesignTokens.secondaryText(colorScheme))
                    }
                }
            }
        } else if case .failed(let message) = viewModel.pairingService.receiverState {
            Label(message, systemImage: "clock.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            ProgressView("Démarrage du service d'appairage…")
                .adaptiveSmallControlSize()
        }
    }

    private func instructionRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(step)
                .font(.system(.callout, design: .monospaced, weight: .bold))
                .foregroundStyle(DesignTokens.accent(accentTheme, colorScheme))
                .frame(width: 28, height: 28)
                .background(DesignTokens.accent(accentTheme, colorScheme).opacity(0.16), in: Circle())
            Text(text)
                .font(.callout)
                .foregroundStyle(DesignTokens.primaryText(colorScheme))
            Spacer()
        }
    }

    // MARK: - Actions

    private func activateCurrentMode() async {
        hasAppliedPayload = false
        switch roleMode {
        case .receiver:
            viewModel.discoveryService.stopPairingDiscovery()
            await restartReceiver()
        case .sender:
            viewModel.pairingService.stopReceiver()
            viewModel.pairingService.resetSender()
            viewModel.discoveryService.startPairingDiscovery()
        }
    }

    private func restartReceiver() async {
        await viewModel.pairingService.startReceiver(
            deviceName: Self.currentDeviceName(),
            relayBaseURL: resolvedRelayURL,
            apiClient: resolvedRelayURL != nil ? viewModel.apiClient : nil
        )
    }

    private func sendPayload() async {
        isSending = true
        _ = await viewModel.pairAppleTV(target: selectedTarget, pin: sanitizedPIN)
        isSending = false
    }

    private func cleanup() {
        viewModel.discoveryService.stopPairingDiscovery()
        viewModel.pairingService.stopReceiver()
    }

    private static func currentDeviceName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Apple TV"
        #endif
    }
}
