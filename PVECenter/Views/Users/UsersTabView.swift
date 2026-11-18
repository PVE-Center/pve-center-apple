import SwiftUI

private enum UserFilter: String, CaseIterable, Identifiable {
    case all = "Tous"
    case synced = "Jellyseerr"
    case unsynced = "À importer"
    case disabled = "Suspendus"

    var id: String { rawValue }
}

public struct UsersTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme
    @State private var filter: UserFilter = .all
    @State private var showCreateSheet = false
    @State private var selectedUser: UnifiedUser?
    @State private var isSyncing = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var displayedUsers: [UnifiedUser] {
        let all = viewModel.usersOverview?.users ?? []
        let q = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return all.filter { user in
            let matchesSearch = q.isEmpty || user.name.lowercased().contains(q)
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .synced: user.inJellyseerr
            case .unsynced: !user.inJellyseerr
            case .disabled: user.isDisabled
            }
            return matchesSearch && matchesFilter
        }
    }

    private var adaptiveColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 740), spacing: 24)]
        #elseif os(macOS)
        return [GridItem(.adaptive(minimum: 310), spacing: 12)]
        #else
        return [GridItem(.flexible())]
        #endif
    }

    private var gridRowSpacing: CGFloat {
        #if os(tvOS)
        return 22
        #else
        return 12
        #endif
    }

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return 14
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: sectionSpacing) {
                headerActionsCard

                HStack(spacing: 12) {
                    Text("Comptes (\(displayedUsers.count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .lineLimit(1)
                    Spacer()
                    AdaptiveSegmentedControl(
                        options: UserFilter.allCases,
                        selection: $filter,
                        title: \.rawValue
                    )
                }

                LazyVGrid(columns: adaptiveColumns, spacing: gridRowSpacing) {
                    ForEach(displayedUsers) { user in
                        userRow(user)
                    }
                }

                if displayedUsers.isEmpty {
                    GlassCard {
                        ContentUnavailableView(
                            "Aucun utilisateur",
                            systemImage: "person.slash",
                            description: Text("Aucun compte ne correspond à votre recherche ou filtre.")
                        )
                    }
                }
            }
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
            .padding(.vertical, DesignTokens.pageVerticalPadding)
        }
        #if os(tvOS)
        .contentMargins(.top, 18, for: .scrollContent)
        .contentMargins(.bottom, 32, for: .scrollContent)
        .fullScreenCover(isPresented: $showCreateSheet) {
            CreateUserSheet(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $selectedUser) { user in
            ManageUserSheet(viewModel: viewModel, user: user)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
        }
        #else
        .contentMargins(.top, 8, for: .scrollContent)
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: filter)
        #endif
        .sheet(isPresented: $showCreateSheet) {
            CreateUserSheet(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        .sheet(item: $selectedUser) { user in
            ManageUserSheet(viewModel: viewModel, user: user)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        #endif
    }

    private var headerActionsCard: some View {
        let counts = viewModel.usersOverview?.counts

        return GlassCard(padding: {
            #if os(tvOS)
            20
            #else
            16
            #endif
        }()) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jellyfin ↔ Jellyseerr")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            .lineLimit(1)
                        Text("\(counts?.totalJellyfin ?? 0) comptes • \(counts?.syncedJellyseerr ?? 0) synchronisés")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer()
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Créer", systemImage: "person.badge.plus")
                            #if os(tvOS)
                            .font(.callout.weight(.semibold))
                            #else
                            .frame(minHeight: 28)
                            #endif
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                    .adaptiveSmallControlSize()
                }

                if let unsynced = counts?.unsyncedCount, unsynced > 0 {
                    Button {
                        guard !isSyncing else { return }
                        Task {
                            isSyncing = true
                            await viewModel.syncMissingUsers()
                            isSyncing = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(isSyncing ? "Synchronisation…" : "Importer \(unsynced) compte(s) vers Jellyseerr")
                                #if os(tvOS)
                                .font(.callout.weight(.semibold))
                                #else
                                .font(.caption.weight(.semibold))
                                #endif
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        #if !os(tvOS)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        #endif
                    }
                    .adaptivePillButtonStyle()
                    #if !os(tvOS)
                    .disabled(isSyncing)
                    #endif
                }
            }
        }
    }

    private func userRow(_ user: UnifiedUser) -> some View {
        let teal = DesignTokens.accent(accentTheme, colorScheme)
        let critical = DesignTokens.critical(colorScheme)
        let nominal = DesignTokens.nominal(colorScheme)
        let caution = DesignTokens.caution(colorScheme)
        #if os(tvOS)
        let cardPadding: CGFloat = 20
        let avatarSize: CGFloat = 52
        #else
        let cardPadding: CGFloat = 14
        let avatarSize: CGFloat = 40
        #endif

        return Button {
            selectedUser = user
        } label: {
            GlassCard(padding: cardPadding, cornerRadius: 18, interactive: true) {
                HStack(spacing: 14) {
                    Text(String(user.name.prefix(2)).uppercased())
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundStyle(user.isDisabled ? critical : (user.isAdmin ? teal : DesignTokens.primaryText(colorScheme)))
                        .frame(width: avatarSize, height: avatarSize)
                        .background(
                            DesignTokens.surfaceElevated(theme: accentTheme, colorScheme),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(user.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            if user.isProtected == true {
                                Image(systemName: "shield.checkmark.fill")
                                    #if os(tvOS)
                                    .font(.caption)
                                    #else
                                    .font(.caption2)
                                    #endif
                                    .foregroundStyle(teal)
                                    .accessibilityLabel("Compte propriétaire protégé")
                            }
                            if user.isAdmin {
                                StatusPill("Admin", color: teal, systemImage: "crown.fill")
                            }
                            if user.isDisabled {
                                StatusPill("Suspendu", color: critical, systemImage: "nosign")
                            }
                        }

                        HStack(spacing: 6) {
                            Text(user.inJellyseerr ? "Jellyseerr: \(user.autoApprove ? "Auto" : "Manuel")" : "Non importé")
                                #if os(tvOS)
                                .font(.caption)
                                #else
                                .font(.caption2)
                                #endif
                                .foregroundStyle(user.inJellyseerr ? nominal : caution)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            Text("•")
                                #if os(tvOS)
                                .font(.caption)
                                #else
                                .font(.caption2)
                                #endif
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            Text("Activité: \(ByteFormatters.formatRelativeISO(user.lastActivity))")
                                #if os(tvOS)
                                .font(.caption)
                                #else
                                .font(.caption2)
                                #endif
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .font(.subheadline)
                }
                .frame(minHeight: 52)
            }
        }
        .cardButtonStyle(cornerRadius: 18)
    }
}

public struct MaxActiveSessionsControl: View {
    @Binding public var maxActiveSessions: Int

    public init(maxActiveSessions: Binding<Int>) {
        self._maxActiveSessions = maxActiveSessions
    }

    public var body: some View {
        #if os(tvOS)
        Picker("Écrans simultanés", selection: $maxActiveSessions) {
            Text("Illimité").tag(0)
            ForEach(1...10, id: \.self) { count in
                Text(count == 1 ? "1 écran" : "\(count) écrans").tag(count)
            }
        }
        #else
        Stepper(
            maxActiveSessions == 0 ? "Écrans simultanés : Illimité" : "Écrans simultanés : \(maxActiveSessions)",
            value: $maxActiveSessions,
            in: 0...10
        )
        #endif
    }
}
