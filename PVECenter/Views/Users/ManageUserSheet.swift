import SwiftUI

public struct ManageUserSheet: View {
    public var viewModel: AppViewModel
    public let user: UnifiedUser
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var isDisabled: Bool
    @State private var isAdmin: Bool
    @State private var enableAllFolders: Bool
    @State private var selectedFolders: Set<String>
    @State private var enableDownloading: Bool
    @State private var maxActiveSessions: Int
    @State private var autoApprove: Bool

    @State private var newPassword: String = ""
    @State private var isSaving: Bool = false
    @State private var confirmDelete: Bool = false

    public init(viewModel: AppViewModel, user: UnifiedUser) {
        self.viewModel = viewModel
        self.user = user
        _isDisabled = State(initialValue: user.isDisabled)
        _isAdmin = State(initialValue: user.isAdmin)
        _enableAllFolders = State(initialValue: user.enableAllFolders)
        _selectedFolders = State(initialValue: Set(user.enabledFolders))
        _enableDownloading = State(initialValue: user.enableDownloading)
        _maxActiveSessions = State(initialValue: user.maxActiveSessions)
        _autoApprove = State(initialValue: user.autoApprove)
    }

    private var isProtectedOwner: Bool {
        user.isProtected == true
    }

    private var libraries: [JellyfinLibrary] {
        viewModel.usersOverview?.libraries ?? []
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
                                Text(user.name)
                                    .font(.largeTitle.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                Text("Rôles, accès médiathèques, sécurité & Jellyseerr")
                                    .font(.callout)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                            Spacer()
                            Button("Fermer") { dismiss() }
                                .adaptivePillButtonStyle()
                            Button {
                                guard !isSaving else { return }
                                Task { await submitSave() }
                            } label: {
                                Text(isSaving ? "Enregistrement…" : "Enregistrer")
                                    .opacity(isSaving ? 0.5 : 1.0)
                            }
                            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                        }
                        .focusSection()

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Statut & Rôle")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                statusRoleFields
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Médiathèques & Quotas")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                librariesAndQuotasFields
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Jellyseerr")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                jellyseerrFields
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Sécurité")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                securityFields
                            }
                        }

                        if !isProtectedOwner {
                            GlassCard(padding: 24, cornerRadius: 22) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Zone de danger")
                                            .font(.headline)
                                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                        Text("Supprime définitivement ce compte de Jellyfin et Jellyseerr.")
                                            .font(.caption)
                                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                    }
                                    Spacer()
                                    Button("Supprimer le compte", role: .destructive) {
                                        confirmDelete = true
                                    }
                                    .adaptivePillButtonStyle(tint: DesignTokens.critical(colorScheme))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 1120)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(
                "Supprimer définitivement « \(user.name) » ?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        isSaving = true
                        let ok = await viewModel.deleteUser(id: user.jellyfinId, name: user.name)
                        isSaving = false
                        if ok { dismiss() }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ce compte sera supprimé de Jellyfin et de Jellyseerr.")
            }
            #else
            Form {
                Section("Statut & Rôle") { statusRoleFields }
                Section("Médiathèques & Quotas") { librariesAndQuotasFields }
                Section("Jellyseerr") { jellyseerrFields }
                Section("Sécurité") { securityFields }

                if !isProtectedOwner {
                    Section {
                        Button("Supprimer le compte (Jellyfin + Jellyseerr)", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .adaptiveTVOSModalFormContainer()
            .navigationTitle(user.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Enregistrement…" : "Enregistrer") {
                        Task { await submitSave() }
                    }
                    .disabled(isSaving)
                }
            }
            .confirmationDialog(
                "Supprimer définitivement « \(user.name) » ?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        isSaving = true
                        let ok = await viewModel.deleteUser(id: user.jellyfinId, name: user.name)
                        isSaving = false
                        if ok { dismiss() }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ce compte sera supprimé de Jellyfin et de Jellyseerr.")
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 500)
        #endif
    }

    @ViewBuilder
    private var statusRoleFields: some View {
        if isProtectedOwner {
            Label("Compte propriétaire protégé : suspension, rétrogradation et suppression verrouillées.", systemImage: "shield.checkmark.fill")
                .font(.caption)
                .foregroundStyle(.indigo)
        }
        Toggle("Compte suspendu (Jellyfin)", isOn: $isDisabled)
            .disabled(isProtectedOwner)
        Toggle("Administrateur Jellyfin", isOn: $isAdmin)
            .disabled(isProtectedOwner)
    }

    @ViewBuilder
    private var librariesAndQuotasFields: some View {
        Toggle("Toutes les médiathèques", isOn: $enableAllFolders)
        if !enableAllFolders {
            ForEach(libraries) { library in
                let included = selectedFolders.contains(library.id)
                Button {
                    if included {
                        selectedFolders.remove(library.id)
                    } else {
                        selectedFolders.insert(library.id)
                    }
                } label: {
                    HStack {
                        Text(library.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if included {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DesignTokens.accent(accentTheme, colorScheme))
                        }
                    }
                }
            }
        }

        Toggle("Téléchargement autorisé", isOn: $enableDownloading)
        MaxActiveSessionsControl(maxActiveSessions: $maxActiveSessions)
    }

    @ViewBuilder
    private var jellyseerrFields: some View {
        if user.inJellyseerr {
            Toggle("Auto-approbation des demandes", isOn: $autoApprove)
                .disabled(isProtectedOwner)
            HStack {
                Text("Demandes effectuées")
                Spacer()
                Text("\(user.requestCount)")
                    .foregroundStyle(.secondary)
            }
        } else {
            Button("Importer dans Jellyseerr maintenant") {
                Task {
                    await viewModel.syncMissingUsers(userIDs: [user.jellyfinId])
                    dismiss()
                }
            }
            #if os(tvOS)
            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
            #endif
        }
    }

    @ViewBuilder
    private var securityFields: some View {
        HStack {
            SecureField("Nouveau mot de passe (min. 4 car.)", text: $newPassword)
            Button("Appliquer") {
                guard !(newPassword.count < 4 || isSaving) else { return }
                Task {
                    isSaving = true
                    let ok = await viewModel.resetPassword(id: user.jellyfinId, newPassword: newPassword)
                    isSaving = false
                    if ok { newPassword = "" }
                }
            }
            #if os(tvOS)
            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme))
            .opacity((newPassword.count < 4 || isSaving) ? 0.45 : 1.0)
            #else
            .disabled(newPassword.count < 4 || isSaving)
            #endif
        }
    }

    private func submitSave() async {
        isSaving = true
        let payload = UpdateUserRequest(
            isDisabled: isProtectedOwner ? nil : isDisabled,
            isAdmin: isProtectedOwner ? nil : isAdmin,
            enableAllFolders: enableAllFolders,
            enabledFolders: enableAllFolders ? [] : Array(selectedFolders),
            enableDownloading: enableDownloading,
            maxActiveSessions: maxActiveSessions,
            autoApprove: user.inJellyseerr && !isProtectedOwner ? autoApprove : nil
        )
        let ok = await viewModel.updateUser(id: user.jellyfinId, payload: payload)
        isSaving = false
        if ok { dismiss() }
    }
}
