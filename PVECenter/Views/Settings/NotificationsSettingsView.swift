import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#endif

public struct NotificationsSettingsView: View {
    public var viewModel: AppViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme
    #if os(iOS)
    @Environment(\.openURL) private var openURL
    #endif

    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var testingKey: String?
    @State private var lastTestResult: TestNotificationResult?
    @State private var lastTestLatencyMs: Int?

    @State private var showAPNsEditor: Bool = false
    @State private var apnsDraft: APNsConfigSummary = APNsConfigSummary()

    @State private var editingWebhook: NotificationChannelConfig?
    @State private var isAddingWebhook: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var channels: NotificationChannelsResponse {
        viewModel.notificationChannels ?? NotificationChannelsResponse()
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
            .navigationTitle("Notifications & Alertes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                #if !os(tvOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await loadData() }
                    } label: {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading || isSaving)
                }
                #endif
            }
            #if os(tvOS)
            .fullScreenCover(isPresented: $isAddingWebhook) {
                WebhookChannelEditorSheet(
                    existing: nil,
                    onSave: { newChannel in
                        await saveWebhook(newChannel, isNew: true)
                    }
                )
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
            }
            .fullScreenCover(item: $editingWebhook) { channel in
                WebhookChannelEditorSheet(
                    existing: channel,
                    onSave: { updated in
                        await saveWebhook(updated, isNew: false)
                    }
                )
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
            }
            #else
            .sheet(isPresented: $isAddingWebhook) {
                WebhookChannelEditorSheet(
                    existing: nil,
                    onSave: { newChannel in
                        await saveWebhook(newChannel, isNew: true)
                    }
                )
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
            }
            .sheet(item: $editingWebhook) { channel in
                WebhookChannelEditorSheet(
                    existing: channel,
                    onSave: { updated in
                        await saveWebhook(updated, isNew: false)
                    }
                )
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
            }
            #endif
        }
        #if os(tvOS)
        .preferredColorScheme(.dark)
        #elseif os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 560)
        #endif
        .task {
            await loadData()
        }
    }

    // MARK: - iOS & macOS Form Layout

    #if !os(tvOS)
    private var standardLayout: some View {
        Form {
            localPermissionsSection
            apnsServerSection
            webhooksSection
            globalTestSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background { AmbientBackgroundView() }
    }

    private var localPermissionsSection: some View {
        Section {
            HStack {
                Label("Statut Apple Notifications", systemImage: authorizationIcon)
                    .foregroundStyle(authorizationColor)
                Spacer()
                StatusPill(authorizationLabel, color: authorizationColor, systemImage: authorizationIcon)
            }

            if viewModel.pushManager.authorizationStatus == .notDetermined {
                Button {
                    Task { _ = await viewModel.requestPushAuthorization() }
                } label: {
                    Label("Activer les notifications sur cet appareil", systemImage: "bell.badge.fill")
                }
                .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true, cornerRadius: 12)
            } else if viewModel.pushManager.authorizationStatus == .denied {
                #if os(iOS)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Ouvrir les Réglages système", systemImage: "gear")
                }
                #else
                Text("Activez les notifications pour PVE Center dans Réglages Système → Notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }

            Toggle(
                "Alertes locales en premier plan",
                isOn: Binding(
                    get: { viewModel.pushManager.localNotificationsEnabled },
                    set: { viewModel.pushManager.localNotificationsEnabled = $0 }
                )
            )

            if let tokenHex = viewModel.pushManager.deviceTokenHex, !tokenHex.isEmpty {
                LabeledContent("Jeton APNs appareil") {
                    Text("\(String(tokenHex.prefix(12)))…")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let err = viewModel.pushManager.lastRegistrationError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Permissions appareil local")
        }
    }

    private var apnsServerSection: some View {
        let apns = channels.apns
        return Section {
            HStack {
                Label("Service Push APNs serveur", systemImage: apns.enabled ? "apple.logo" : "bell.slash")
                Spacer()
                StatusPill(
                    apns.enabled ? "Activé" : "Désactivé",
                    color: apns.enabled ? DesignTokens.nominal(colorScheme) : .secondary,
                    systemImage: apns.enabled ? "checkmark.circle.fill" : "minus.circle"
                )
            }

            LabeledContent("Configuration APNs") {
                StatusPill(
                    apns.keyConfigured ? "Configurée" : "Incomplète",
                    color: apns.keyConfigured ? DesignTokens.nominal(colorScheme) : DesignTokens.caution(colorScheme),
                    systemImage: apns.keyConfigured ? "key.fill" : "exclamationmark.triangle.fill"
                )
            }

            LabeledContent("Clé privée .p8") {
                StatusPill(
                    apns.privateKeyExists ? "Présente" : "Absente",
                    color: apns.privateKeyExists ? DesignTokens.nominal(colorScheme) : DesignTokens.caution(colorScheme),
                    systemImage: apns.privateKeyExists ? "checkmark.shield.fill" : "doc.questionmark"
                )
            }

            LabeledContent("Appareils enregistrés", value: "\(apns.registeredDevicesCount)")
            if !apns.bundleId.isEmpty {
                LabeledContent("Bundle ID", value: apns.bundleId)
                    .font(.caption)
            }
            LabeledContent("Environnement", value: apns.useSandbox ? "Sandbox (Dev)" : "Production")

            Button {
                Task { await runTest(channelId: nil, channelType: "apns", key: "apns") }
            } label: {
                HStack {
                    Label("Tester la notification APNs", systemImage: "paperplane.fill")
                    Spacer()
                    if testingKey == "apns" {
                        ProgressView()
                            .adaptiveSmallControlSize()
                    }
                }
            }
            .disabled(testingKey != nil)

            DisclosureGroup("Paramètres APNs serveur", isExpanded: $showAPNsEditor) {
                Toggle("Activer APNs", isOn: $apnsDraft.enabled)
                TextField("Team ID (10 caractères)", text: $apnsDraft.teamId)
                    .autocorrectionDisabled()
                TextField("Key ID (.p8)", text: $apnsDraft.keyId)
                    .autocorrectionDisabled()
                TextField("Bundle ID", text: $apnsDraft.bundleId)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Chemin clé .p8", text: $apnsDraft.privateKeyPath)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Toggle("Utiliser APNs Sandbox", isOn: $apnsDraft.useSandbox)

                Button {
                    Task { await saveAPNsDraft() }
                } label: {
                    Label(isSaving ? "Enregistrement…" : "Enregistrer APNs", systemImage: "checkmark.circle.fill")
                }
                .disabled(isSaving)
            }
        } header: {
            Text("Apple Push Notification Service (Serveur)")
        }
    }

    private var webhooksSection: some View {
        Section {
            if channels.webhooks.isEmpty {
                Text("Aucun webhook configuré. Ajoutez Discord, Telegram, ntfy, Gotify ou Home Assistant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(channels.webhooks) { webhook in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: webhookIcon(for: webhook.type))
                                .foregroundStyle(webhookColor(for: webhook.type))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(webhook.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(webhookTypeLabel(for: webhook.type))
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(webhookColor(for: webhook.type).opacity(0.15), in: Capsule())
                                        .foregroundStyle(webhookColor(for: webhook.type))
                                }
                                Text(webhookDestinationSummary(webhook))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { webhook.enabled },
                                    set: { newVal in
                                        var updated = webhook
                                        updated.enabled = newVal
                                        Task { await saveWebhook(updated, isNew: false) }
                                    }
                                )
                            )
                            .labelsHidden()
                        }

                        HStack(spacing: 12) {
                            if webhook.notifyOnDown {
                                Text("Hors ligne")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if webhook.notifyOnRecovery {
                                Text("Rétablissement")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Button {
                                Task { await runTest(channelId: webhook.id, channelType: webhook.type, key: webhook.id) }
                            } label: {
                                if testingKey == webhook.id {
                                    ProgressView().adaptiveSmallControlSize()
                                } else {
                                    Label("Tester", systemImage: "paperplane")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .buttonStyle(.bordered)
                            .adaptiveSmallControlSize()
                            .disabled(testingKey != nil)

                            Button {
                                editingWebhook = webhook
                            } label: {
                                Label("Modifier", systemImage: "pencil")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .adaptiveSmallControlSize()

                            Button(role: .destructive) {
                                Task { await deleteWebhook(id: webhook.id) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Supprimer \(webhook.name)")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                isAddingWebhook = true
            } label: {
                Label("Ajouter un webhook (Discord / Telegram / ntfy…)", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Webhooks & Intégrations (\(channels.webhooks.count))")
        }
    }

    private var globalTestSection: some View {
        Section("Tests & Livraison") {
            Button {
                Task { await runTest(channelId: nil, channelType: "all", key: "all") }
            } label: {
                HStack {
                    Label("Tester tous les canaux actifs", systemImage: "bolt.horizontal.circle.fill")
                        .fontWeight(.semibold)
                    Spacer()
                    if testingKey == "all" {
                        ProgressView().adaptiveSmallControlSize()
                    }
                }
            }
            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true, cornerRadius: 12)
            .disabled(testingKey != nil)

            if let result = lastTestResult {
                testResultsList(result)
            }
        }
    }
    #endif

    // MARK: - tvOS 10-Foot Layout

    #if os(tvOS)
    private var tvOSLayout: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications & Alertes")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            Text("Permissions locales, statut APNs du serveur et test des webhooks.")
                                .font(.callout)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                        Spacer()
                        Button {
                            guard testingKey == nil else { return }
                            Task { await runTest(channelId: nil, channelType: "all", key: "all") }
                        } label: {
                            Label(testingKey == "all" ? "Envoi…" : "Tout tester", systemImage: "paperplane.fill")
                                .font(.callout.weight(.semibold))
                                .opacity(testingKey != nil ? 0.55 : 1.0)
                        }
                        .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)

                        Button {
                            guard !(isLoading || isSaving) else { return }
                            Task { await loadData() }
                        } label: {
                            Label("Actualiser", systemImage: "arrow.clockwise")
                                .font(.callout.weight(.semibold))
                        }
                        .adaptivePillButtonStyle()

                        Button {
                            dismiss()
                        } label: {
                            Label("Fermer", systemImage: "xmark.circle.fill")
                                .font(.callout.weight(.semibold))
                        }
                        .adaptivePillButtonStyle()
                    }
                    .focusSection()

                    HStack(alignment: .top, spacing: 28) {
                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Appareil & Serveur APNs", systemImage: "bell.badge.fill")
                                    .font(.title3.weight(.bold))
                                HStack {
                                    Text("Permissions Apple TV")
                                    Spacer()
                                    StatusPill(authorizationLabel, color: authorizationColor, systemImage: authorizationIcon)
                                }
                                if viewModel.pushManager.authorizationStatus == .notDetermined {
                                    Button("Autoriser les alertes") {
                                        Task { _ = await viewModel.requestPushAuthorization() }
                                    }
                                    .font(.callout.weight(.semibold))
                                    .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme))
                                }
                                Divider()
                                let apns = channels.apns
                                HStack {
                                    Text("APNs Serveur")
                                    Spacer()
                                    StatusPill(
                                        apns.keyConfigured ? "Configuré" : "Incomplet",
                                        color: apns.keyConfigured ? DesignTokens.nominal(colorScheme) : DesignTokens.caution(colorScheme),
                                        systemImage: "key.fill"
                                    )
                                }
                                Text("Clé .p8 : \(apns.privateKeyExists ? "Présente" : "Absente") • Appareils : \(apns.registeredDevicesCount)")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                        }
                        .frame(maxWidth: .infinity)

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Webhooks (\(channels.webhooks.count))", systemImage: "arrow.triangle.branch")
                                        .font(.title3.weight(.bold))
                                    Spacer()
                                    Button {
                                        isAddingWebhook = true
                                    } label: {
                                        Label("Ajouter", systemImage: "plus")
                                            .font(.callout.weight(.semibold))
                                    }
                                    .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                                }

                                if channels.webhooks.isEmpty {
                                    Text("Aucun webhook configuré.")
                                        .font(.callout)
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                } else {
                                    ForEach(channels.webhooks) { wh in
                                        HStack(spacing: 12) {
                                            Image(systemName: webhookIcon(for: wh.type))
                                                .foregroundStyle(webhookColor(for: wh.type))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(wh.name)
                                                    .font(.headline)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                Text("\(webhookTypeLabel(for: wh.type)) • \(wh.enabled ? "Actif" : "Inactif")")
                                                    .font(.caption)
                                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Button("Tester") {
                                                Task { await runTest(channelId: wh.id, channelType: wh.type, key: wh.id) }
                                            }
                                            .font(.callout.weight(.semibold))
                                            .adaptivePillButtonStyle()
                                            Button {
                                                editingWebhook = wh
                                            } label: {
                                                Image(systemName: "pencil")
                                            }
                                            .adaptivePillButtonStyle()
                                            .accessibilityLabel("Modifier \(wh.name)")
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let result = lastTestResult {
                        GlassCard(padding: 24, cornerRadius: 22) {
                            testResultsList(result)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    #endif

    // MARK: - Shared Helpers

    @ViewBuilder
    private func testResultsList(_ result: TestNotificationResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusPill(
                    result.ok ? "Tests réussis" : "Résultat partiel",
                    color: result.ok ? DesignTokens.nominal(colorScheme) : DesignTokens.caution(colorScheme),
                    systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                if let latency = lastTestLatencyMs {
                    Text("\(latency) ms")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let summary = result.message, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(result.results) { item in
                HStack(alignment: .top, spacing: 10) {
                    let isSkipped = item.skipped == true
                    Image(systemName: item.ok ? "checkmark.circle.fill" : (isSkipped ? "forward.circle.fill" : "xmark.octagon.fill"))
                        .foregroundStyle(item.ok ? .green : (isSkipped ? .orange : .red))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.name ?? item.channelType.uppercased())
                                .font(.caption.weight(.semibold))
                            if let code = item.httpStatus {
                                Text("HTTP \(code)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                        Text(item.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var authorizationLabel: String {
        switch viewModel.pushManager.authorizationStatus {
        case .authorized: return "Autorisées"
        case .provisional: return "Provisoires"
        #if os(iOS)
        case .ephemeral: return "Éphémères"
        #endif
        case .denied: return "Refusées"
        case .notDetermined: return "Non demandées"
        @unknown default: return "Inconnu"
        }
    }

    private var authorizationColor: Color {
        switch viewModel.pushManager.authorizationStatus {
        case .authorized, .provisional: return DesignTokens.nominal(colorScheme)
        #if os(iOS)
        case .ephemeral: return DesignTokens.nominal(colorScheme)
        #endif
        case .denied: return DesignTokens.critical(colorScheme)
        case .notDetermined: return DesignTokens.caution(colorScheme)
        @unknown default: return .secondary
        }
    }

    private var authorizationIcon: String {
        switch viewModel.pushManager.authorizationStatus {
        case .authorized, .provisional: return "bell.badge.fill"
        #if os(iOS)
        case .ephemeral: return "bell.badge.fill"
        #endif
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell.circle"
        @unknown default: return "bell"
        }
    }

    private func webhookIcon(for type: String) -> String {
        switch type.lowercased() {
        case "discord": return "bubble.left.and.bubble.right.fill"
        case "telegram": return "paperplane.fill"
        default: return "network"
        }
    }

    private func webhookColor(for type: String) -> Color {
        switch type.lowercased() {
        case "discord": return .indigo
        case "telegram": return .cyan
        default: return DesignTokens.accent(accentTheme, colorScheme)
        }
    }

    private func webhookTypeLabel(for type: String) -> String {
        switch type.lowercased() {
        case "discord": return "Discord"
        case "telegram": return "Telegram"
        default: return "Générique / ntfy / HA"
        }
    }

    private func webhookDestinationSummary(_ webhook: NotificationChannelConfig) -> String {
        if webhook.type.lowercased() == "telegram" {
            let chat = webhook.chatId ?? ""
            return chat.isEmpty ? "Telegram Bot" : "Chat ID : \(chat)"
        }
        return webhook.url ?? "URL non définie"
    }

    // MARK: - Data Actions

    private func loadData() async {
        isLoading = true
        await viewModel.pushManager.refreshAuthorizationStatus()
        await viewModel.refreshNotificationChannels()
        apnsDraft = channels.apns
        isLoading = false
    }

    private func saveAPNsDraft() async {
        isSaving = true
        var updated = channels
        updated.apns = apnsDraft
        _ = await viewModel.saveNotificationChannels(updated)
        apnsDraft = channels.apns
        isSaving = false
    }

    private func saveWebhook(_ webhook: NotificationChannelConfig, isNew: Bool) async {
        isSaving = true
        var updated = channels
        if isNew {
            updated.webhooks.append(webhook)
        } else if let idx = updated.webhooks.firstIndex(where: { $0.id == webhook.id }) {
            updated.webhooks[idx] = webhook
        }
        _ = await viewModel.saveNotificationChannels(updated)
        isSaving = false
    }

    private func deleteWebhook(id: String) async {
        isSaving = true
        var updated = channels
        updated.webhooks.removeAll { $0.id == id }
        _ = await viewModel.saveNotificationChannels(updated)
        isSaving = false
    }

    private func runTest(channelId: String?, channelType: String?, key: String) async {
        testingKey = key
        let clock = ContinuousClock()
        let start = clock.now
        let result = await viewModel.testNotificationChannel(channelId: channelId, channelType: channelType)
        let duration = clock.now - start
        let ms = Int(duration.components.seconds * 1000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
        lastTestResult = result
        lastTestLatencyMs = max(1, ms)
        testingKey = nil
    }
}

// MARK: - Webhook Add / Edit Sheet

private struct WebhookChannelEditorSheet: View {
    let existing: NotificationChannelConfig?
    let onSave: (NotificationChannelConfig) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var name: String = ""
    @State private var type: String = "discord"
    @State private var enabled: Bool = true
    @State private var url: String = ""
    @State private var botToken: String = ""
    @State private var chatId: String = ""
    @State private var headersText: String = ""
    @State private var notifyOnDown: Bool = true
    @State private var notifyOnRecovery: Bool = true
    @State private var includeDetails: Bool = true
    @State private var isSaving: Bool = false

    private var isEditing: Bool { existing != nil }

    init(existing: NotificationChannelConfig?, onSave: @escaping (NotificationChannelConfig) async -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _type = State(initialValue: existing?.type ?? "discord")
        _enabled = State(initialValue: existing?.enabled ?? true)
        _url = State(initialValue: existing?.url ?? "")
        _botToken = State(initialValue: "")
        _chatId = State(initialValue: existing?.chatId ?? "")
        let initialHeaders = (existing?.headers ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        _headersText = State(initialValue: initialHeaders)
        _notifyOnDown = State(initialValue: existing?.notifyOnDown ?? true)
        _notifyOnRecovery = State(initialValue: existing?.notifyOnRecovery ?? true)
        _includeDetails = State(initialValue: existing?.includeDetails ?? true)
    }

    private var isFormValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        if type == "telegram" {
            let hasChat = !chatId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasToken = !botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (existing?.botTokenSet == true)
            return hasChat && hasToken
        }
        return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            #if os(tvOS)
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isEditing ? "Modifier le webhook" : "Nouveau webhook")
                                    .font(.largeTitle.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                Text("Discord, Telegram ou endpoint HTTP / ntfy / Gotify")
                                    .font(.callout)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                            Spacer()
                            Button("Annuler") { dismiss() }
                                .adaptivePillButtonStyle()
                            Button {
                                guard isFormValid && !isSaving else { return }
                                Task { await commit() }
                            } label: {
                                Text(isSaving ? "Enregistrement…" : "Enregistrer")
                                    .opacity(isFormValid && !isSaving ? 1.0 : 0.45)
                            }
                            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                        }
                        .focusSection()

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Canal")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                channelFields
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(type == "telegram" ? "Paramètres Telegram" : (type == "discord" ? "Webhook Discord" : "Webhook HTTP / ntfy / Gotify / HA"))
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                destinationFields
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Déclencheurs")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                triggerFields
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 1080)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            #else
            Form {
                Section("Canal") { channelFields }

                if type == "telegram" {
                    Section("Paramètres Telegram") { destinationFields }
                } else {
                    Section(type == "discord" ? "Webhook Discord" : "Webhook HTTP / ntfy / Gotify / HA") {
                        destinationFields
                    }
                }

                Section("Déclencheurs") { triggerFields }
            }
            .adaptiveTVOSModalFormContainer()
            .navigationTitle(isEditing ? "Modifier le webhook" : "Nouveau webhook")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Enregistrement…" : "Enregistrer") {
                        Task { await commit() }
                    }
                    .disabled(!isFormValid || isSaving)
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 460)
        #endif
    }

    @ViewBuilder
    private var channelFields: some View {
        TextField("Nom (ex: Discord Homelab, ntfy Mobile)", text: $name)

        Picker("Type", selection: $type) {
            Text("Discord").tag("discord")
            Text("Telegram").tag("telegram")
            Text("Générique / ntfy / Gotify / HA").tag("generic")
        }

        Toggle("Canal actif", isOn: $enabled)
    }

    @ViewBuilder
    private var destinationFields: some View {
        if type == "telegram" {
            SecureField(
                existing?.botTokenSet == true ? "Token du bot (défini — laisser vide pour conserver)" : "Bot Token (@BotFather)",
                text: $botToken
            )
            TextField("Chat ID (ex: -100123456789)", text: $chatId)
                .autocorrectionDisabled()
        } else {
            TextField(
                type == "discord" ? "https://discord.com/api/webhooks/..." : "https://ntfy.sh/mon-topic",
                text: $url
            )
            .autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif

            if type == "generic" {
                TextField("En-têtes HTTP (un par ligne : Clé: Valeur)", text: $headersText, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(.caption, design: .monospaced))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
        }
    }

    @ViewBuilder
    private var triggerFields: some View {
        Toggle("Alerter quand un service tombe", isOn: $notifyOnDown)
        Toggle("Alerter lors du rétablissement", isOn: $notifyOnRecovery)
        Toggle("Inclure les détails & latence", isOn: $includeDetails)
    }

    private func commit() async {
        isSaving = true
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedToken: String? = if !trimmedToken.isEmpty {
            trimmedToken
        } else if existing?.botTokenSet == true {
            existing?.botToken ?? "********"
        } else {
            nil
        }

        var parsedHeaders: [String: String]? = nil
        if type == "generic" {
            var dict: [String: String] = [:]
            for line in headersText.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let k = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let v = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !k.isEmpty { dict[k] = v }
                }
            }
            if !dict.isEmpty { parsedHeaders = dict }
        }

        let payload = NotificationChannelConfig(
            id: existing?.id ?? "wh-\(UUID().uuidString.prefix(8).lowercased())",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            enabled: enabled,
            url: type == "telegram" ? nil : (trimmedURL.isEmpty ? nil : trimmedURL),
            botToken: type == "telegram" ? resolvedToken : nil,
            botTokenSet: existing?.botTokenSet,
            chatId: type == "telegram" ? chatId.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            headers: parsedHeaders,
            notifyOnDown: notifyOnDown,
            notifyOnRecovery: notifyOnRecovery,
            includeDetails: includeDetails
        )

        await onSave(payload)
        isSaving = false
        dismiss()
    }
}
