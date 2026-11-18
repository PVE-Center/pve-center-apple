import SwiftUI

public struct CreateUserSheet: View {
    public var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var syncJellyseerr: Bool = true
    @State private var autoApprove: Bool = true
    @State private var enableAllFolders: Bool = true
    @State private var selectedFolders: Set<String> = []
    @State private var enableDownloading: Bool = true
    @State private var maxActiveSessions: Int = 2
    @State private var isSubmitting: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var libraries: [JellyfinLibrary] {
        viewModel.usersOverview?.libraries ?? []
    }

    private var isValid: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && password.count >= 4
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
                                Text("Nouvel utilisateur")
                                    .font(.largeTitle.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                Text("Compte Jellyfin, quotas et synchronisation Jellyseerr")
                                    .font(.callout)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                            Spacer()
                            Button("Annuler") { dismiss() }
                                .adaptivePillButtonStyle()
                            Button {
                                guard isValid && !isSubmitting else { return }
                                Task { await submitCreate() }
                            } label: {
                                Text(isSubmitting ? "Création…" : "Créer")
                                    .opacity(isValid && !isSubmitting ? 1.0 : 0.45)
                            }
                            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                        }
                        .focusSection()

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Identifiants Jellyfin")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                credentialsFields
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Médiathèques autorisées")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                librariesFields
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Quotas & Téléchargements")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                quotasFields
                            }
                        }

                        GlassCard(padding: 24, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Synchronisation Jellyseerr")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                syncFields
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
            #else
            Form {
                Section("Identifiants Jellyfin") { credentialsFields }
                Section("Médiathèques autorisées") { librariesFields }
                Section("Quotas & Téléchargements") { quotasFields }
                Section("Synchronisation Jellyseerr") { syncFields }
            }
            .adaptiveTVOSModalFormContainer()
            .navigationTitle("Nouvel utilisateur")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Création…" : "Créer") {
                        Task { await submitCreate() }
                    }
                    .disabled(!isValid || isSubmitting)
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 460)
        #endif
    }

    @ViewBuilder
    private var credentialsFields: some View {
        TextField("Nom d'utilisateur (min. 2 car.)", text: $username)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        SecureField("Mot de passe (min. 4 car.)", text: $password)
    }

    @ViewBuilder
    private var librariesFields: some View {
        Toggle("Accès à toutes les médiathèques", isOn: $enableAllFolders)
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
    }

    @ViewBuilder
    private var quotasFields: some View {
        Toggle("Téléchargement hors-ligne autorisé", isOn: $enableDownloading)
        MaxActiveSessionsControl(maxActiveSessions: $maxActiveSessions)
    }

    @ViewBuilder
    private var syncFields: some View {
        Toggle("Créer aussi sur Jellyseerr", isOn: $syncJellyseerr)
        if syncJellyseerr {
            Toggle("Approbation automatique des demandes", isOn: $autoApprove)
        }
    }

    private func submitCreate() async {
        isSubmitting = true
        let ok = await viewModel.createUser(
            CreateUserRequest(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                syncJellyseerr: syncJellyseerr,
                autoApprove: autoApprove,
                enableAllFolders: enableAllFolders,
                enabledFolders: enableAllFolders ? [] : Array(selectedFolders),
                enableDownloading: enableDownloading,
                maxActiveSessions: maxActiveSessions
            )
        )
        isSubmitting = false
        if ok { dismiss() }
    }
}
