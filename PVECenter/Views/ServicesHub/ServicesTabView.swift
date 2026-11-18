import SwiftUI

private enum ServicesFilter: String, CaseIterable, Identifiable {
    case all = "Tous"
    case custom = "Personnalisés"
    case offline = "Hors ligne"

    var id: String { rawValue }
}

public struct ServicesTabView: View {
    public var viewModel: AppViewModel
    #if !os(tvOS)
    @Environment(\.openURL) private var openURL
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var filter: ServicesFilter = .all
    @State private var showAddSheet: Bool = false
    @State private var editingService: CustomServiceConfig?
    @State private var editingCategoryService: CategoryServiceDraft?
    @State private var pendingDeleteService: CustomServiceConfig?
    @State private var testingServiceID: String?
    @State private var inlineTestResults: [String: CustomServiceTestResult] = [:]

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var adaptiveColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 760), spacing: 24)]
        #elseif os(macOS)
        return [GridItem(.adaptive(minimum: 320), spacing: 14)]
        #else
        return [GridItem(.flexible())]
        #endif
    }

    private var gridRowSpacing: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return 14
        #endif
    }

    private var categorySpacing: CGFloat {
        #if os(tvOS)
        return 28
        #else
        return 18
        #endif
    }

    private var sortedCustomServices: [CustomServiceConfig] {
        viewModel.customServices.sorted {
            if $0.order == $1.order {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.order < $1.order
        }
    }

    private var filteredCustomServices: [CustomServiceConfig] {
        let q = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sortedCustomServices.filter { svc in
            let matchesQuery = q.isEmpty
                || svc.name.lowercased().contains(q)
                || svc.description.lowercased().contains(q)
                || svc.category.lowercased().contains(q)
                || (svc.host?.lowercased().contains(q) ?? false)
                || (svc.url?.lowercased().contains(q) ?? false)
            let matchesFilter: Bool = switch filter {
            case .all, .custom: true
            case .offline: !svc.isOnline
            }
            return matchesQuery && matchesFilter
        }
    }

    private var displayedCategories: [ServiceCategory] {
        guard filter != .custom else { return [] }
        let base = viewModel.filteredCategories
        guard filter == .offline else { return base }
        return base.compactMap { category in
            let down = category.services.filter { !$0.online }
            return down.isEmpty ? nil : ServiceCategory(name: category.name, services: down)
        }
    }

    private var canReorderCustomServices: Bool {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filter != .offline
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: categorySpacing) {
                headerCard

                if !filteredCustomServices.isEmpty || filter == .custom {
                    customServicesSection
                }

                ForEach(displayedCategories) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(category.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                            Spacer()
                            Text("\(category.services.filter(\.online).count)/\(category.services.count) en ligne")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                        }

                        LazyVGrid(columns: adaptiveColumns, spacing: gridRowSpacing) {
                            ForEach(Array(category.services.enumerated()), id: \.element.id) { index, service in
                                serviceCard(
                                    service,
                                    categoryName: category.name,
                                    canMoveUp: canReorderCustomServices && index > 0,
                                    canMoveDown: canReorderCustomServices && index < category.services.count - 1
                                )
                            }
                        }
                    }
                }

                if filteredCustomServices.isEmpty && displayedCategories.isEmpty {
                    GlassCard {
                        ContentUnavailableView(
                            "Aucun service trouvé",
                            systemImage: "magnifyingglass",
                            description: Text("Ajoutez un service personnalisé ou ajustez votre filtre.")
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
        #else
        .contentMargins(.top, 8, for: .scrollContent)
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
        #endif
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: filter)
        #endif
        #if os(tvOS)
        .fullScreenCover(isPresented: $showAddSheet) {
            CustomServiceEditorSheet(viewModel: viewModel, existingService: nil)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $editingService) { service in
            CustomServiceEditorSheet(viewModel: viewModel, existingService: service)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $editingCategoryService) { draft in
            CategoryServiceEditorSheet(viewModel: viewModel, draft: draft)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: .dark))
                .preferredColorScheme(.dark)
        }
        #else
        .sheet(isPresented: $showAddSheet) {
            CustomServiceEditorSheet(viewModel: viewModel, existingService: nil)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        .sheet(item: $editingService) { service in
            CustomServiceEditorSheet(viewModel: viewModel, existingService: service)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        .sheet(item: $editingCategoryService) { draft in
            CategoryServiceEditorSheet(viewModel: viewModel, draft: draft)
                .environment(\.accentTheme, viewModel.accentTheme)
                .tint(viewModel.tintColor(for: colorScheme))
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        #endif
        .confirmationDialog(
            pendingDeleteService.map { "Supprimer « \($0.name) » ?" } ?? "",
            isPresented: Binding(
                get: { pendingDeleteService != nil },
                set: { if !$0 { pendingDeleteService = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let svc = pendingDeleteService {
                Button("Supprimer", role: .destructive) {
                    Task { _ = await viewModel.deleteCustomService(id: svc.id) }
                }
                Button("Annuler", role: .cancel) {}
            }
        } message: {
            Text("Cette sonde et son historique de supervision seront retirés de la configuration.")
        }
    }

    // MARK: - Header & Custom Services Section

    private var headerCard: some View {
        let teal = DesignTokens.accent(accentTheme, colorScheme)
        let customOnline = viewModel.customServices.filter(\.isOnline).count
        let catServices = viewModel.categories.flatMap(\.services)
        let catOnline = catServices.filter(\.online).count

        return GlassCard(padding: {
            #if os(tvOS)
            20
            #else
            14
            #endif
        }(), cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Hub de services & sondes")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            .lineLimit(1)
                        Text("\(catOnline + customOnline)/\(catServices.count + viewModel.customServices.count) en ligne • \(viewModel.customServices.count) personnalisé(s)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 8)
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Ajouter un service", systemImage: "plus")
                            #if os(tvOS)
                            .font(.callout.weight(.semibold))
                            #else
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 28)
                            #endif
                            .lineLimit(1)
                    }
                    .adaptivePillButtonStyle(tint: teal, prominent: true)
                    .adaptiveSmallControlSize()
                }

                AdaptiveSegmentedControl(
                    options: ServicesFilter.allCases,
                    selection: $filter,
                    title: \.rawValue
                )
            }
        }
    }

    private var customServicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sondes & Services personnalisés (\(filteredCustomServices.count))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    .lineLimit(1)
                Spacer()
                if viewModel.customServices.count > 1 && canReorderCustomServices {
                    Text("Réorganiser ↑↓")
                        #if os(tvOS)
                        .font(.caption)
                        #else
                        .font(.caption2)
                        #endif
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                }
            }

            if filteredCustomServices.isEmpty {
                GlassCard(padding: 18, cornerRadius: 16) {
                    HStack {
                        Label("Aucun service personnalisé configuré.", systemImage: "plus.app")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        Spacer()
                        Button("Ajouter") {
                            showAddSheet = true
                        }
                        .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)
                        .adaptiveSmallControlSize()
                    }
                }
            } else {
                LazyVGrid(columns: adaptiveColumns, spacing: gridRowSpacing) {
                    ForEach(Array(filteredCustomServices.enumerated()), id: \.element.id) { index, service in
                        customServiceCard(service, index: index, total: filteredCustomServices.count)
                    }
                }
            }
        }
    }

    // MARK: - Custom Service Card

    private func customServiceCard(_ service: CustomServiceConfig, index: Int, total: Int) -> some View {
        let nominal = DesignTokens.nominal(colorScheme)
        let caution = DesignTokens.caution(colorScheme)
        let critical = DesignTokens.critical(colorScheme)
        let muted = isServiceMuted(service)
        let isBusyTesting = testingServiceID == service.id
        let latestTest = inlineTestResults[service.id]
        #if os(tvOS)
        let cardPadding: CGFloat = 20
        let iconSize: CGFloat = 52
        let actionSpacing: CGFloat = 12
        #else
        let cardPadding: CGFloat = 14
        let iconSize: CGFloat = 40
        let actionSpacing: CGFloat = 6
        #endif

        return GlassCard(padding: cardPadding, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ServiceIconView(
                        icon: service.icon,
                        serviceId: service.id,
                        serviceName: service.name,
                        widget: nil,
                        isOnline: service.isOnline,
                        size: iconSize
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(service.name)
                                .font(.headline)
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            protocolBadge(
                                ServiceSymbolCatalog.shortProtocolBadge(service.`protocol`),
                                symbol: service.`protocol`.systemImage
                            )

                            Spacer(minLength: 4)

                            if !service.enabled {
                                StatusPill("Pause", color: DesignTokens.secondaryText(colorScheme), systemImage: "pause.circle.fill")
                            } else if let latency = service.latencyMs, service.isOnline {
                                StatusPill("\(latency) ms", color: nominal, systemImage: "checkmark.circle.fill")
                            } else {
                                StatusPill(
                                    service.isOnline ? "En ligne" : "Hors ligne",
                                    color: service.isOnline ? nominal : critical,
                                    systemImage: service.isOnline ? "checkmark.circle.fill" : "xmark.octagon.fill"
                                )
                            }
                        }

                        if !service.description.isEmpty {
                            Text(service.description)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(2)
                        }

                        HStack(spacing: 8) {
                            Text(targetSubtitle(for: service))
                                #if os(tvOS)
                                .font(.system(.caption, design: .monospaced))
                                #else
                                .font(.system(.caption2, design: .monospaced))
                                #endif
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if muted {
                                StatusPill("Sourdine", color: caution, systemImage: "bell.slash.fill")
                            }
                        }
                    }
                }

                if let metrics = service.metrics, !metrics.isEmpty {
                    metricsBadgeStrip(metrics)
                }

                if let test = latestTest {
                    HStack(spacing: 6) {
                        Image(systemName: test.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            #if os(tvOS)
                            .font(.caption)
                            #else
                            .font(.caption2)
                            #endif
                            .foregroundStyle(test.ok ? nominal : critical)
                        Text("\(test.message) (\(test.latencyMs) ms)")
                            #if os(tvOS)
                            .font(.caption.weight(.medium))
                            #else
                            .font(.caption2.weight(.medium))
                            #endif
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (test.ok ? nominal : critical).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                } else if let msg = service.lastError ?? service.message, !msg.isEmpty, !service.isOnline {
                    Text(msg)
                        #if os(tvOS)
                        .font(.caption)
                        #else
                        .font(.caption2)
                        #endif
                        .foregroundStyle(critical)
                        .lineLimit(1)
                }

                HStack(spacing: actionSpacing) {
                    Button {
                        guard !isBusyTesting else { return }
                        Task {
                            testingServiceID = service.id
                            if let res = await viewModel.testCustomService(id: service.id) {
                                inlineTestResults[service.id] = res
                            }
                            testingServiceID = nil
                        }
                    } label: {
                        Label(isBusyTesting ? "Test…" : "Tester", systemImage: "bolt.horizontal.circle")
                            #if os(tvOS)
                            .font(.callout.weight(.semibold))
                            #else
                            .font(.caption.weight(.semibold))
                            #endif
                            .lineLimit(1)
                    }
                    .adaptivePillButtonStyle()
                    #if !os(tvOS)
                    .disabled(isBusyTesting)
                    #endif
                    .adaptiveSmallControlSize()

                    Button {
                        editingService = service
                    } label: {
                        Label("Modifier", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .adaptivePillButtonStyle()
                    .adaptiveSmallControlSize()
                    .accessibilityLabel("Modifier \(service.name)")

                    Button {
                        Task {
                            if muted {
                                await viewModel.unmuteServiceAlerts(serviceId: service.id)
                            } else {
                                await viewModel.muteServiceAlerts(serviceId: service.id, minutes: 60)
                            }
                        }
                    } label: {
                        Label(muted ? "Réactiver alertes" : "Sourdine 1h", systemImage: muted ? "bell.badge.fill" : "bell.slash")
                            .labelStyle(.iconOnly)
                    }
                    .adaptivePillButtonStyle(tint: muted ? caution : nil)
                    .adaptiveSmallControlSize()
                    .accessibilityLabel(muted ? "Lever la sourdine de \(service.name)" : "Mettre \(service.name) en sourdine 1h")

                    if canReorderCustomServices && total > 1 {
                        if index > 0 {
                            Button {
                                Task { await moveCustomService(at: index, offset: -1) }
                            } label: {
                                Label("Monter", systemImage: "arrow.up")
                                    .labelStyle(.iconOnly)
                            }
                            .adaptivePillButtonStyle()
                            .adaptiveSmallControlSize()
                            .accessibilityLabel("Monter \(service.name)")
                        }

                        if index < total - 1 {
                            Button {
                                Task { await moveCustomService(at: index, offset: 1) }
                            } label: {
                                Label("Descendre", systemImage: "arrow.down")
                                    .labelStyle(.iconOnly)
                            }
                            .adaptivePillButtonStyle()
                            .adaptiveSmallControlSize()
                            .accessibilityLabel("Descendre \(service.name)")
                        }
                    }

                    Spacer(minLength: 4)

                    #if !os(tvOS)
                    if let rawURL = service.url, let webURL = URL(string: rawURL),
                       webURL.scheme?.lowercased().hasPrefix("http") == true {
                        Button {
                            openURL(webURL)
                        } label: {
                            Label("Ouvrir", systemImage: "arrow.up.right")
                                .labelStyle(.iconOnly)
                        }
                        .adaptivePillButtonStyle()
                        .adaptiveSmallControlSize()
                        .accessibilityLabel("Ouvrir \(service.name) dans le navigateur")
                    }
                    #endif

                    Button(role: .destructive) {
                        pendingDeleteService = service
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .adaptivePillButtonStyle(tint: critical)
                    .adaptiveSmallControlSize()
                    .accessibilityLabel("Supprimer \(service.name)")
                }
            }
        }
    }

    // MARK: - Categorized Service Card

    private func serviceCard(
        _ service: ServiceItem,
        categoryName: String,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        let nominal = DesignTokens.nominal(colorScheme)
        let critical = DesignTokens.critical(colorScheme)
        let matchingCustom = viewModel.customServices.first(where: { $0.id == service.id })
        let protoBadge = ServiceSymbolCatalog.shortProtocolBadge(raw: service.protocolType)
            ?? (matchingCustom.map { ServiceSymbolCatalog.shortProtocolBadge($0.`protocol`) })
            ?? (service.url.lowercased().hasPrefix("http") ? "HTTP" : nil)
        let metrics = service.metrics ?? matchingCustom?.metrics
        #if os(tvOS)
        let cardPadding: CGFloat = 20
        let iconSize: CGFloat = 52
        let actionSpacing: CGFloat = 12
        #else
        let cardPadding: CGFloat = 14
        let iconSize: CGFloat = 40
        let actionSpacing: CGFloat = 8
        #endif

        return GlassCard(padding: cardPadding, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ServiceIconView(
                        icon: service.icon,
                        serviceId: service.id,
                        serviceName: service.name,
                        widget: service.widget,
                        isOnline: service.online,
                        size: iconSize
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(service.name)
                                .font(.headline)
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            if let protoBadge {
                                protocolBadge(protoBadge, symbol: nil)
                            }

                            Spacer(minLength: 4)
                            if let latency = service.latencyMs, service.online {
                                StatusPill(String(format: "%.0f ms", latency), color: nominal, systemImage: "checkmark.circle.fill")
                            } else {
                                StatusPill(
                                    service.online ? "En ligne" : "Hors ligne",
                                    color: service.online ? nominal : critical,
                                    systemImage: service.online ? "checkmark.circle.fill" : "xmark.octagon.fill"
                                )
                            }
                        }
                        Text(service.description)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            .lineLimit(2)
                    }
                }

                if let metrics, !metrics.isEmpty {
                    metricsBadgeStrip(metrics)
                }

                if let widgetKey = service.widget?.lowercased() {
                    widgetStrip(for: widgetKey)
                }

                #if os(tvOS)
                if !service.url.isEmpty {
                    Label(service.url, systemImage: "network")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                #endif

                HStack(spacing: actionSpacing) {
                    #if !os(tvOS)
                    if let url = URL(string: service.url), !service.url.isEmpty {
                        Button {
                            openURL(url)
                        } label: {
                            HStack {
                                Label("Ouvrir l'interface web", systemImage: "safari")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .adaptivePillButtonStyle()
                    }
                    #endif

                    if let matchingCustom {
                        Button {
                            Task {
                                testingServiceID = matchingCustom.id
                                if let res = await viewModel.testCustomService(id: matchingCustom.id) {
                                    inlineTestResults[matchingCustom.id] = res
                                }
                                testingServiceID = nil
                            }
                        } label: {
                            Label("Tester", systemImage: "bolt.horizontal.circle")
                                #if os(tvOS)
                                .font(.callout.weight(.semibold))
                                #else
                                .font(.caption.weight(.semibold))
                                #endif
                        }
                        .adaptivePillButtonStyle()
                        .adaptiveSmallControlSize()

                        Button {
                            editingService = matchingCustom
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                                #if os(tvOS)
                                .labelStyle(.titleAndIcon)
                                .font(.callout.weight(.semibold))
                                #else
                                .labelStyle(.iconOnly)
                                #endif
                        }
                        .adaptivePillButtonStyle()
                        .adaptiveSmallControlSize()
                    } else {
                        if canMoveUp {
                            Button {
                                Task { await viewModel.moveCategoryService(id: service.id, direction: "up") }
                            } label: {
                                Label("Monter", systemImage: "arrow.up")
                                    .labelStyle(.iconOnly)
                            }
                            .adaptivePillButtonStyle()
                            .adaptiveSmallControlSize()
                            .accessibilityLabel("Monter \(service.name)")
                        }

                        if canMoveDown {
                            Button {
                                Task { await viewModel.moveCategoryService(id: service.id, direction: "down") }
                            } label: {
                                Label("Descendre", systemImage: "arrow.down")
                                    .labelStyle(.iconOnly)
                            }
                            .adaptivePillButtonStyle()
                            .adaptiveSmallControlSize()
                            .accessibilityLabel("Descendre \(service.name)")
                        }

                        Button {
                            editingCategoryService = CategoryServiceDraft(
                                categoryName: categoryName,
                                service: service
                            )
                        } label: {
                            Label("Personnaliser", systemImage: "pencil")
                                #if os(tvOS)
                                .labelStyle(.titleAndIcon)
                                .font(.callout.weight(.semibold))
                                #else
                                .labelStyle(.iconOnly)
                                #endif
                        }
                        .adaptivePillButtonStyle()
                        .adaptiveSmallControlSize()
                        .accessibilityLabel("Personnaliser \(service.name)")
                    }

                    #if os(tvOS)
                    Spacer(minLength: 4)
                    #endif
                }
            }
        }
    }

    // MARK: - Subcomponents & Helpers

    private func protocolBadge(_ label: String, symbol: String?) -> some View {
        let teal = DesignTokens.accent(accentTheme, colorScheme)
        return HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    #if os(tvOS)
                    .font(.caption2.weight(.bold))
                    #else
                    .font(.system(size: 9, weight: .bold))
                    #endif
            }
            Text(label)
                #if os(tvOS)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                #else
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                #endif
        }
        .foregroundStyle(teal)
        #if os(tvOS)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        #else
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        #endif
        .background(
            teal.opacity(colorScheme == .light ? 0.11 : 0.16),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(teal.opacity(0.28), lineWidth: 0.7)
        )
        .fixedSize()
    }

    private func metricsBadgeStrip(_ metrics: [String: JSONValue]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(metrics.keys.sorted(), id: \.self) { key in
                    if let value = metrics[key] {
                        HStack(spacing: 4) {
                            Text(key.replacingOccurrences(of: "_", with: " "))
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            Text(value.displayString)
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            DesignTokens.surfaceElevated(theme: accentTheme, colorScheme),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                }
            }
        }
    }

    private func targetSubtitle(for service: CustomServiceConfig) -> String {
        switch service.`protocol` {
        case .httpRest, .jsonMetrics:
            return service.healthUrl ?? service.url ?? service.internalUrl ?? service.category
        case .tcpPort:
            if let host = service.host, let port = service.port {
                return "\(host):\(port)"
            }
            return service.host ?? service.category
        case .icmpPing:
            return service.host ?? service.category
        case .webhookIngest:
            return service.message ?? "TTL \(service.webhookTtlSeconds)s"
        }
    }

    private func isServiceMuted(_ service: CustomServiceConfig) -> Bool {
        guard let mutedUntil = service.mutedUntil, !mutedUntil.isEmpty else { return false }
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractional.date(from: mutedUntil) ?? ISO8601DateFormatter().date(from: mutedUntil) {
            return date > Date()
        }
        return false
    }

    private func moveCustomService(at index: Int, offset: Int) async {
        let targetIndex = index + offset
        var current = filteredCustomServices
        guard current.indices.contains(index), current.indices.contains(targetIndex) else { return }
        current.swapAt(index, targetIndex)
        await viewModel.reorderCustomServices(serviceIds: current.map(\.id))
    }

    @ViewBuilder
    private func widgetStrip(for key: String) -> some View {
        switch key {
        case "jellyfin":
            if let jf = viewModel.widgets?.jellyfin {
                HStack(spacing: 8) {
                    miniStat("Flux", "\(jf.activeStreamsCount ?? 0)")
                    miniStat("Films", "\(jf.moviesCount ?? 0)")
                    miniStat("Séries", "\(jf.seriesCount ?? 0)")
                }
            }
        case "plex":
            if let plex = viewModel.widgets?.plex {
                HStack(spacing: 8) {
                    miniStat("Flux", "\(plex.activeStreamsCount ?? 0)")
                    miniStat("Librairies", "\(plex.librariesCount ?? 0)")
                }
            }
        case "radarr":
            if let radarr = viewModel.widgets?.radarr {
                HStack(spacing: 8) {
                    miniStat("Films", "\(radarr.moviesDownloaded ?? 0)/\(radarr.moviesTotal ?? 0)")
                    miniStat("File", "\(radarr.queueCount ?? 0)")
                    miniStat("Manquants", "\(radarr.moviesMissing ?? 0)")
                }
            }
        case "sonarr":
            if let sonarr = viewModel.widgets?.sonarr {
                HStack(spacing: 8) {
                    miniStat("Séries", "\(sonarr.seriesTotal ?? 0)")
                    miniStat("Épisodes", "\(sonarr.episodesDownloaded ?? 0)")
                    miniStat("File", "\(sonarr.queueCount ?? 0)")
                }
            }
        case "prowlarr":
            if let prowlarr = viewModel.widgets?.prowlarr {
                HStack(spacing: 8) {
                    miniStat("Indexeurs", "\(prowlarr.indexersEnabled ?? 0)/\(prowlarr.indexersTotal ?? 0)")
                    miniStat("Grabs", "\(prowlarr.grabs ?? 0)")
                }
            }
        case "qbittorrent":
            if let qbit = viewModel.widgets?.qbittorrent {
                HStack(spacing: 8) {
                    miniStat("DL", ByteFormatters.formatSpeed(qbit.dlSpeedBytes))
                    miniStat("UP", ByteFormatters.formatSpeed(qbit.upSpeedBytes))
                    miniStat("Torrents", "\(qbit.torrentsTotal ?? 0)")
                }
            }
        default:
            EmptyView()
        }
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                #if os(tvOS)
                .font(.caption)
                #else
                .font(.caption2)
                #endif
                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(value)
                #if os(tvOS)
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                #else
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                #endif
                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(DesignTokens.surfaceElevated(theme: accentTheme, colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
