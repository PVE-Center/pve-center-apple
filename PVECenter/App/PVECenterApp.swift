import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

private extension Notification.Name {
    static let pveDidRegisterAPNsToken = Notification.Name("PVECenter.didRegisterAPNsToken")
}

#if os(iOS) && canImport(UIKit)
@MainActor
final class PVEAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationCenter.default.post(name: .pveDidRegisterAPNsToken, object: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Safely ignored when aps-environment entitlement is absent (e.g. personal team or simulator).
        _ = error
    }
}
#elseif os(macOS) && canImport(AppKit)
@MainActor
final class PVEAppDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationCenter.default.post(name: .pveDidRegisterAPNsToken, object: deviceToken)
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Safely ignored when aps-environment entitlement is absent.
        _ = error
    }
}
#endif

@main
public struct PVECenterApp: App {
    @State private var viewModel = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS) && canImport(UIKit)
    @UIApplicationDelegateAdaptor(PVEAppDelegate.self) private var appDelegate
    #elseif os(macOS) && canImport(AppKit)
    @NSApplicationDelegateAdaptor(PVEAppDelegate.self) private var appDelegate
    #endif

    public init() {}

    public var body: some Scene {
        WindowGroup("PVE Center", id: "main") {
            ContentView(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                #if os(tvOS)
                .preferredColorScheme(.dark)
                #else
                .preferredColorScheme(viewModel.preferredColorScheme)
                #endif
                .onOpenURL { url in
                    Task { await viewModel.handleIncomingURL(url) }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        viewModel.handleScenePhaseChanged(isBackground: false)
                    case .background:
                        viewModel.handleScenePhaseChanged(isBackground: true)
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
                #if !os(tvOS)
                .onReceive(NotificationCenter.default.publisher(for: .pveDidRegisterAPNsToken)) { notification in
                    if let data = notification.object as? Data {
                        Task { await viewModel.handleRegisteredDeviceToken(data) }
                    }
                }
                .onChange(of: viewModel.pushManager.authorizationStatus) { _, _ in
                    registerRemoteNotificationsIfAuthorized()
                }
                .task {
                    await viewModel.pushManager.refreshAuthorizationStatus()
                    registerRemoteNotificationsIfAuthorized()
                }
                #endif
                #if os(macOS)
                .frame(minWidth: 880, minHeight: 580)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandMenu("Supervision") {
                Button("Rafraîchir maintenant") {
                    Task { await viewModel.refreshAll(silent: false) }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(viewModel.autoRefresh ? "Mettre l'actualisation auto en pause" : "Activer l'actualisation auto (5s)") {
                    viewModel.toggleAutoRefresh()
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Connexion Serveur & Mode Démo…") {
                    viewModel.showServerSettings = true
                }
                .keyboardShortcut(";", modifiers: .command)

                Button("Assistant d'installation…") {
                    viewModel.relaunchOnboarding()
                }

                Divider()

                ForEach(Array(AppTab.allCases.enumerated()), id: \.element.id) { index, tab in
                    Button(tab.title) {
                        viewModel.selectedTab = tab
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
        #endif

        #if os(macOS)
        Settings {
            ServerSettingsSheet(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .preferredColorScheme(viewModel.preferredColorScheme)
        }

        MenuBarExtra("PVE Center", systemImage: "server.rack") {
            MenuBarPanelView(viewModel: viewModel)
                .environment(\.accentTheme, viewModel.accentTheme)
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        .menuBarExtraStyle(.window)
        #endif
    }

    #if !os(tvOS)
    private func registerRemoteNotificationsIfAuthorized() {
        let status = viewModel.pushManager.authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        #if os(iOS) && canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS) && canImport(AppKit)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }
    #endif
}

#if os(macOS)
private struct MenuBarPanelView: View {
    var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let teal = DesignTokens.accent(viewModel.accentTheme, colorScheme)
        let nominal = DesignTokens.nominal(colorScheme)
        let caution = DesignTokens.caution(colorScheme)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("PVE Center", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                StatusPill(
                    viewModel.isDemoMode ? "Mode Démo" : (viewModel.pveOverview?.online == true ? "En ligne" : "Hors ligne"),
                    color: viewModel.isDemoMode ? teal : (viewModel.pveOverview?.online == true ? nominal : caution),
                    systemImage: viewModel.isDemoMode ? "sparkles" : (viewModel.pveOverview?.online == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                )
            }

            Divider()

            if let node = viewModel.pveOverview?.node {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Nœud \(node.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        Spacer()
                        Text("\(viewModel.pveOverview?.counts.running ?? 0)/\(viewModel.pveOverview?.counts.total ?? 0) actifs")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                    HStack {
                        Text("CPU \(String(format: "%.1f %%", node.cpuPct))")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text("RAM \(String(format: "%.0f %%", node.memPct))")
                            .font(.system(.caption, design: .monospaced))
                    }
                    UsageProgressBar(percentage: node.cpuPct, tint: teal)
                    UsageProgressBar(percentage: node.memPct, tint: DesignTokens.secondaryText(colorScheme))
                }
            } else {
                Text("Aucune télémétrie chargée. Ouvrez la fenêtre principale ou activez le Mode Démo.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
            }

            if let pool = viewModel.pveOverview?.externalStorage?.pool {
                HStack {
                    Label(pool.name, systemImage: "internaldrive.fill")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("\(ByteFormatters.formatDecimalTB(pool.usedBytes)) / \(ByteFormatters.formatDecimalTB(pool.totalBytes))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                }
            }

            if let qbit = viewModel.widgets?.qbittorrent {
                HStack {
                    Label("qBittorrent", systemImage: "arrow.down.arrow.up.circle")
                        .font(.caption)
                    Spacer()
                    Text("↓ \(ByteFormatters.formatSpeed(qbit.dlSpeedBytes))  ↑ \(ByteFormatters.formatSpeed(qbit.upSpeedBytes))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                }
            }

            if let streams = viewModel.widgets?.jellyfin?.activeStreamsCount, streams > 0 {
                HStack {
                    Label("Jellyfin", systemImage: "play.tv.fill")
                        .font(.caption)
                        .foregroundStyle(teal)
                    Spacer()
                    Text("\(streams) flux actif\(streams > 1 ? "s" : "")")
                        .font(.caption2.weight(.semibold))
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.refreshAll(silent: false) }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }

                if viewModel.opsOverview?.qbitControl.available == true {
                    let turtle = viewModel.opsOverview?.qbitControl.altSpeedEnabled == true
                    Button {
                        Task { await viewModel.toggleQbitSpeedMode() }
                    } label: {
                        Label(turtle ? "Tortue ON" : "Tortue", systemImage: "tortoise.fill")
                    }
                    .tint(turtle ? .orange : .secondary)
                }

                Spacer()

                Button("Ouvrir") {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quitter", systemImage: "power")
                        .labelStyle(.iconOnly)
                }
                .help("Quitter PVE Center")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
    }
}
#endif
