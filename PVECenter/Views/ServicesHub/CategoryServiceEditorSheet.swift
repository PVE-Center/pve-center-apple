import SwiftUI

public struct CategoryServiceDraft: Identifiable, Hashable, Sendable {
    public let id: String
    public let categoryName: String
    public let service: ServiceItem

    public init(categoryName: String, service: ServiceItem) {
        self.id = service.id
        self.categoryName = categoryName
        self.service = service
    }

    public static func == (lhs: CategoryServiceDraft, rhs: CategoryServiceDraft) -> Bool {
        lhs.id == rhs.id && lhs.categoryName == rhs.categoryName && lhs.service == rhs.service
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(categoryName)
    }
}

private struct WidgetOption: Identifiable {
    let id: String
    let label: String
}

private let WIDGET_OPTIONS: [WidgetOption] = [
    WidgetOption(id: "", label: "Aucun widget"),
    WidgetOption(id: "jellyfin", label: "Jellyfin (flux & médiathèque)"),
    WidgetOption(id: "plex", label: "Plex (flux & librairies)"),
    WidgetOption(id: "radarr", label: "Radarr (films & file)"),
    WidgetOption(id: "sonarr", label: "Sonarr (séries & épisodes)"),
    WidgetOption(id: "prowlarr", label: "Prowlarr (indexeurs & grabs)"),
    WidgetOption(id: "qbittorrent", label: "qBittorrent (débit DL/UP)"),
]

public struct CategoryServiceEditorSheet: View {
    public var viewModel: AppViewModel
    public let draft: CategoryServiceDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var name: String
    @State private var description: String
    @State private var category: String
    @State private var icon: String
    @State private var url: String
    @State private var pingUrl: String
    @State private var widget: String

    @State private var isTesting: Bool = false
    @State private var testResult: CategoryServiceTestResponse?
    @State private var isSaving: Bool = false
    @State private var isDeleting: Bool = false
    @State private var confirmDelete: Bool = false

    public init(viewModel: AppViewModel, draft: CategoryServiceDraft) {
        self.viewModel = viewModel
        self.draft = draft
        _name = State(initialValue: draft.service.name)
        _description = State(initialValue: draft.service.description)
        _category = State(initialValue: draft.categoryName)
        _icon = State(initialValue: draft.service.icon)
        _url = State(initialValue: draft.service.url)
        _pingUrl = State(initialValue: draft.service.pingUrl ?? "")
        _widget = State(initialValue: draft.service.widget ?? "")
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var categorySuggestions: [String] {
        var list = viewModel.categories.map(\.name)
        for fallback in [
            "Médias & Streaming",
            "Téléchargements & Indexeurs",
            "Cloud, Sécurité & Gaming",
            "Infrastructure & Réseau",
            "Services Personnalisés",
        ] where !list.contains(where: { $0.caseInsensitiveCompare(fallback) == .orderedSame }) {
            list.append(fallback)
        }
        return list
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
                                Text("Personnaliser \(draft.service.name)")
                                    .font(.largeTitle.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .lineLimit(1)
                                Text("Application, icône Homelab, liens et widget temps réel")
                                    .font(.callout)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                            Spacer()
                            Button("Annuler") { dismiss() }
                                .adaptivePillButtonStyle()
                            Button {
                                guard canSubmit && !isSaving else { return }
                                Task { await saveChanges() }
                            } label: {
                                Text(isSaving ? "Enregistrement…" : "Enregistrer")
                                    .opacity(canSubmit && !isSaving ? 1.0 : 0.45)
                            }
                            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                        }
                        .focusSection()

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Application")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                applicationFields
                            }
                        }

                        ServiceIconPickerSection(
                            selectedIcon: $icon,
                            serviceId: draft.service.id,
                            serviceName: name,
                            widget: widget
                        )

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Liens & Supervision")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                linksFields
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Test de joignabilité")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                testControls
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Zone de danger")
                                        .font(.headline)
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    Text("Retire cette application du catalogue sur le serveur.")
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    guard !isDeleting else { return }
                                    confirmDelete = true
                                } label: {
                                    Label(isDeleting ? "Suppression…" : "Retirer du panneau", systemImage: "trash")
                                }
                                .adaptivePillButtonStyle(tint: DesignTokens.critical(colorScheme))
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
            .confirmationDialog(
                "Retirer « \(draft.service.name) » du panneau ?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        isDeleting = true
                        let ok = await viewModel.deleteCategoryService(id: draft.service.id)
                        isDeleting = false
                        if ok { dismiss() }
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
            #else
            Form {
                Section("Application") {
                    applicationFields
                }

                ServiceIconPickerSection(
                    selectedIcon: $icon,
                    serviceId: draft.service.id,
                    serviceName: name,
                    widget: widget
                )

                Section("Liens & Supervision") {
                    linksFields
                }

                Section("Test de joignabilité") {
                    testControls
                }

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label(isDeleting ? "Suppression…" : "Retirer cette application du panneau", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                }
            }
            .adaptiveTVOSModalFormContainer()
            .navigationTitle("Personnaliser")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Enregistrement…" : "Enregistrer") {
                        Task { await saveChanges() }
                    }
                    .disabled(!canSubmit || isSaving)
                }
            }
            .confirmationDialog(
                "Retirer « \(draft.service.name) » du panneau ?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        isDeleting = true
                        let ok = await viewModel.deleteCategoryService(id: draft.service.id)
                        isDeleting = false
                        if ok { dismiss() }
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 560)
        #endif
    }

    @ViewBuilder
    private var applicationFields: some View {
        TextField("Nom affiché", text: $name)
        TextField("Description", text: $description)
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
    }

    @ViewBuilder
    private var linksFields: some View {
        TextField("URL d'ouverture (https://…)", text: $url)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif

        TextField("URL Healthcheck interne (ping_url, optionnelle)", text: $pingUrl)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif

        Picker("Widget temps réel", selection: $widget) {
            ForEach(WIDGET_OPTIONS) { opt in
                Text(opt.label).tag(opt.id)
            }
        }
    }

    @ViewBuilder
    private var testControls: some View {
        Button {
            guard !isTesting else { return }
            Task { await runTest() }
        } label: {
            HStack {
                Label(isTesting ? "Test en cours…" : "Tester maintenant", systemImage: "bolt.horizontal.circle")
                Spacer()
                if isTesting {
                    ProgressView()
                }
            }
        }
        #if os(tvOS)
        .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme))
        #else
        .disabled(isTesting)
        #endif

        if let res = testResult {
            HStack(spacing: 8) {
                Image(systemName: res.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(res.ok ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme))
                Text(res.message)
                    .font(.caption)
                Spacer()
                if let ms = res.latencyMs {
                    Text("\(ms) ms")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                }
            }
        }
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        let payload = CategoryServiceTestRequest(
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            pingUrl: pingUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        testResult = await viewModel.testCategoryService(id: draft.service.id, override: payload)
    }

    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }
        let payload = CategoryServiceUpdateRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            pingUrl: pingUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines),
            widget: widget.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let ok = await viewModel.updateCategoryService(id: draft.service.id, payload: payload)
        if ok {
            dismiss()
        }
    }
}
