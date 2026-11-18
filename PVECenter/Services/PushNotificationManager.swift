import Foundation
import Observation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Foreground / tvOS real-time alert banner model displayed when WebSocket/SSE alert events arrive.
public struct InAppAlertBanner: Identifiable, Equatable, Sendable {
    public let id: String
    public let serviceId: String?
    public let serviceName: String
    public let severity: String
    public let title: String
    public let message: String
    public let timestamp: Date
    public let isResolved: Bool

    public init(
        id: String = UUID().uuidString,
        serviceId: String? = nil,
        serviceName: String,
        severity: String,
        title: String,
        message: String,
        timestamp: Date = Date(),
        isResolved: Bool = false
    ) {
        self.id = id
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.severity = severity
        self.title = title
        self.message = message
        self.timestamp = timestamp
        self.isResolved = isResolved
    }
}

/// Manages APNs registration, local interactive notifications (iOS/macOS),
/// and the live in-app banner queue (especially for tvOS where interactive push categories are unavailable).
@Observable
@MainActor
public final class PushNotificationManager {
    public static let serviceAlertCategoryIdentifier = "SERVICE_ALERT"
    public static let mute1HourActionIdentifier = "MUTE_1H"
    public static let testServiceActionIdentifier = "TEST_SERVICE"

    public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    public private(set) var deviceTokenHex: String?
    public private(set) var lastRegistrationError: String?
    public private(set) var activeBannerQueue: [InAppAlertBanner] = []
    public var localNotificationsEnabled: Bool = true

    public var activeTVBanner: InAppAlertBanner? {
        activeBannerQueue.first
    }

    public var onMuteServiceRequested: (@MainActor (String, Int) async -> Void)?
    public var onTestServiceRequested: (@MainActor (String) async -> Void)?
    public var onNavigateToIncident: (@MainActor (String?) -> Void)?

    private let delegateProxy = NotificationCenterDelegateProxy()
    private var dismissTasks: [String: Task<Void, Never>] = [:]

    public init() {
        delegateProxy.onAction = { [weak self] actionIdentifier, serviceId in
            Task { @MainActor [weak self] in
                await self?.handleNotificationAction(identifier: actionIdentifier, serviceId: serviceId)
            }
        }
        UNUserNotificationCenter.current().delegate = delegateProxy
        registerNotificationCategories()
    }

    // MARK: - Registration & Permissions

    public func registerPushHandlers(
        onMuteService: @escaping @MainActor (String, Int) async -> Void,
        onTestService: @escaping @MainActor (String) async -> Void,
        onOpenIncident: (@MainActor (String?) -> Void)? = nil
    ) {
        self.onMuteServiceRequested = onMuteService
        self.onTestServiceRequested = onTestService
        self.onNavigateToIncident = onOpenIncident
        registerNotificationCategories()
    }

    private func registerNotificationCategories() {
        #if !os(tvOS)
        let muteAction = UNNotificationAction(
            identifier: Self.mute1HourActionIdentifier,
            title: "Mute 1h",
            options: []
        )
        let testAction = UNNotificationAction(
            identifier: Self.testServiceActionIdentifier,
            title: "Tester",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.serviceAlertCategoryIdentifier,
            actions: [muteAction, testAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        #endif
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        #if os(tvOS)
        let options: UNAuthorizationOptions = [.badge]
        #else
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        #endif

        do {
            let granted = try await center.requestAuthorization(options: options)
            await refreshAuthorizationStatus()
            return granted
        } catch {
            lastRegistrationError = error.localizedDescription
            await refreshAuthorizationStatus()
            return false
        }
    }

    public func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    public func registerDeviceToken(
        _ data: Data,
        apiClient: APIClient,
        baseURL: String,
        bearerToken: String?
    ) async {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceTokenHex = hex
        lastRegistrationError = nil

        let normalized = APIClient.normalizeBaseURL(baseURL)
        guard !normalized.isEmpty else { return }

        let request = APNsDeviceRegisterRequest(
            deviceToken: hex,
            platform: Self.currentPlatformName,
            deviceName: Self.currentDeviceName(),
            appVersion: Self.currentAppVersion,
            environment: Self.currentAPNsEnvironment
        )

        do {
            try await apiClient.registerAPNsDevice(
                baseURL: normalized,
                bearerToken: bearerToken,
                demoMode: false,
                payload: request
            )
        } catch {
            lastRegistrationError = error.localizedDescription
        }
    }

    // MARK: - Live Event Handling & Banner Queue

    public func handleRealtimeEvent(
        _ envelope: RealtimeEventEnvelope,
        isAppInBackground: Bool
    ) {
        switch envelope.eventType {
        case .alertTriggered:
            let serviceName = envelope.serviceName ?? envelope.serviceId ?? "Service"
            let title = envelope.title ?? "Alerte : \(serviceName) hors ligne"
            let message = envelope.message ?? "Le service \(serviceName) ne répond plus."
            let severity = envelope.severity ?? "critical"
            let serviceId = envelope.serviceId

            let banner = InAppAlertBanner(
                id: envelope.incidentId ?? "alert-\(serviceId ?? UUID().uuidString)",
                serviceId: serviceId,
                serviceName: serviceName,
                severity: severity,
                title: title,
                message: message,
                isResolved: false
            )
            enqueueBanner(banner, autoDismissAfter: 10.0)

            if localNotificationsEnabled || isAppInBackground {
                postLocalServiceAlert(
                    id: banner.id,
                    serviceId: serviceId,
                    title: title,
                    body: message,
                    isResolved: false
                )
            }

        case .alertResolved:
            let serviceName = envelope.serviceName ?? envelope.serviceId ?? "Service"
            let title = envelope.title ?? "Rétabli : \(serviceName)"
            let message = envelope.message ?? "Le service \(serviceName) est de nouveau opérationnel."
            let serviceId = envelope.serviceId

            let banner = InAppAlertBanner(
                id: "resolved-\(envelope.incidentId ?? serviceId ?? UUID().uuidString)",
                serviceId: serviceId,
                serviceName: serviceName,
                severity: "resolved",
                title: title,
                message: message,
                isResolved: true
            )
            enqueueBanner(banner, autoDismissAfter: 6.0)

            if localNotificationsEnabled && isAppInBackground {
                postLocalServiceAlert(
                    id: banner.id,
                    serviceId: serviceId,
                    title: title,
                    body: message,
                    isResolved: true
                )
            }

        default:
            break
        }
    }

    public func enqueueBanner(_ banner: InAppAlertBanner, autoDismissAfter: TimeInterval = 8.0) {
        activeBannerQueue.removeAll { $0.id == banner.id }
        activeBannerQueue.append(banner)
        if activeBannerQueue.count > 5 {
            let dropped = activeBannerQueue.removeFirst()
            dismissTasks.removeValue(forKey: dropped.id)?.cancel()
        }

        dismissTasks[banner.id]?.cancel()
        if autoDismissAfter > 0 {
            let bannerID = banner.id
            dismissTasks[bannerID] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(autoDismissAfter))
                guard !Task.isCancelled else { return }
                self?.dismissBanner(id: bannerID)
            }
        }
    }

    public func dismissCurrentBanner() {
        guard let first = activeBannerQueue.first else { return }
        dismissBanner(id: first.id)
    }

    public func dismissBanner(id: String) {
        dismissTasks.removeValue(forKey: id)?.cancel()
        activeBannerQueue.removeAll { $0.id == id }
    }

    public func clearAllBanners() {
        for task in dismissTasks.values {
            task.cancel()
        }
        dismissTasks.removeAll()
        activeBannerQueue.removeAll()
    }

    public func postLocalServiceAlert(
        id: String,
        serviceId: String?,
        title: String,
        body: String,
        isResolved: Bool
    ) {
        #if !os(tvOS)
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.serviceAlertCategoryIdentifier
        if let serviceId {
            content.userInfo = [
                "service_id": serviceId,
                "resolved": isResolved,
            ]
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
        #else
        _ = (id, serviceId, title, body, isResolved)
        #endif
    }

    // MARK: - Action Dispatch

    private func handleNotificationAction(identifier: String, serviceId: String?) async {
        #if !os(tvOS)
        switch identifier {
        case Self.mute1HourActionIdentifier:
            if let serviceId {
                await onMuteServiceRequested?(serviceId, 60)
            }
        case Self.testServiceActionIdentifier:
            if let serviceId {
                await onTestServiceRequested?(serviceId)
            }
        case UNNotificationDefaultActionIdentifier:
            onNavigateToIncident?(serviceId)
        default:
            break
        }
        #else
        _ = (identifier, serviceId)
        #endif
    }

    // MARK: - Device Metadata

    private static var currentPlatformName: String {
        #if os(tvOS)
        "tvos"
        #elseif os(macOS)
        "macos"
        #else
        "ios"
        #endif
    }

    private static var currentAPNsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private static func currentDeviceName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Apple Device"
        #endif
    }
}

// MARK: - Sendable UNUserNotificationCenterDelegate Proxy

private final class NotificationCenterDelegateProxy: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    var onAction: (@Sendable (String, String?) -> Void)?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        #if os(tvOS)
        completionHandler([.badge])
        #else
        completionHandler([.banner, .list, .sound])
        #endif
    }

    #if !os(tvOS)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let serviceId = (userInfo["service_id"] as? String) ?? (userInfo["serviceId"] as? String)
        onAction?(actionID, serviceId)
        completionHandler()
    }
    #endif
}
