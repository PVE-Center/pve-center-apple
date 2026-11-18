import SwiftUI
#if os(iOS)
@preconcurrency import AVFoundation
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct QRScannedConnection: Sendable, Equatable {
    public let rawValue: String
    public let baseURL: String
    public let serverName: String
    public let token: String?

    public init(rawValue: String, baseURL: String, serverName: String, token: String? = nil) {
        self.rawValue = rawValue
        self.baseURL = baseURL
        self.serverName = serverName
        self.token = token
    }
}

public struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme
    #if os(iOS)
    @Environment(\.openURL) private var openURL
    #endif

    public let onConnectPayload: (QRScannedConnection) -> Void

    @State private var manualInput: String = ""
    @State private var parseError: String?
    @State private var showManualFallbackSheet: Bool = false
    @State private var torchEnabled: Bool = false

    #if os(iOS)
    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var hasCameraHardware: Bool = AVCaptureDevice.default(for: .video) != nil
    @State private var scanLocked: Bool = false
    #endif

    public init(onConnectPayload: @escaping (QRScannedConnection) -> Void) {
        self.onConnectPayload = onConnectPayload
    }

    public static func parseConnectionInput(_ raw: String) -> QRScannedConnection? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let parsed = AppViewModel.parseConnectDeepLinkPayload(url: url) {
            return QRScannedConnection(
                rawValue: trimmed,
                baseURL: parsed.url,
                serverName: parsed.name,
                token: parsed.token
            )
        }

        // Accept direct http/https server URLs pasted manually or encoded in QR codes.
        let normalized = APIClient.normalizeBaseURL(trimmed)
        if !normalized.isEmpty,
           let parsedURL = URL(string: normalized),
           let scheme = parsedURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           let host = parsedURL.host,
           !host.isEmpty {
            let fallbackName = host.split(separator: ".").first.map(String.init) ?? host
            return QRScannedConnection(
                rawValue: trimmed,
                baseURL: normalized,
                serverName: fallbackName,
                token: nil
            )
        }

        return nil
    }

    public var body: some View {
        NavigationStack {
            Group {
                #if os(iOS)
                iOSBody
                #else
                manualEntryBody
                #endif
            }
            .navigationTitle("Scanner QR Code")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    Button("Saisie manuelle") {
                        showManualFallbackSheet = true
                    }
                }
                #endif
            }
            .sheet(isPresented: $showManualFallbackSheet) {
                NavigationStack {
                    manualEntryBody
                        .navigationTitle("Lien ou URL serveur")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fermer") { showManualFallbackSheet = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 360)
        #endif
    }

    // MARK: - iOS Camera Scanner

    #if os(iOS)
    @ViewBuilder
    private var iOSBody: some View {
        if !hasCameraHardware {
            noCameraFallbackView
        } else {
            switch cameraPermission {
            case .authorized:
                liveCameraScannerView
            case .notDetermined:
                permissionRequestView
            case .denied, .restricted:
                permissionDeniedView
            @unknown default:
                permissionDeniedView
            }
        }
    }

    private var liveCameraScannerView: some View {
        ZStack {
            QRCameraPreviewRepresentable(torchEnabled: torchEnabled) { code in
                handleDetectedCode(code)
            }
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        DesignTokens.accent(accentTheme, .dark),
                        style: StrokeStyle(lineWidth: 3, dash: [24, 14])
                    )
                    .frame(width: 240, height: 240)
                    .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .accessibilityLabel("Cadre de visée pour QR code")

                VStack(spacing: 8) {
                    Text("Pointez la caméra vers le QR code PVE Center")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Format pris en charge : pvecenter://connect?url=... ou URL HTTPS")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)

                if let parseError {
                    Label(parseError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .padding(.horizontal, 20)
                }

                Spacer()

                HStack(spacing: 12) {
                    if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
                        Button {
                            torchEnabled.toggle()
                        } label: {
                            Label(torchEnabled ? "Torche ON" : "Torche", systemImage: torchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                        .adaptiveGlassButtonStyle(prominent: false)
                        .tint(.white)
                    }

                    Button {
                        showManualFallbackSheet = true
                    } label: {
                        Label("Coller un lien", systemImage: "link.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .adaptiveGlassButtonStyle(prominent: true)
                    .tint(DesignTokens.accent(accentTheme, colorScheme))
                }
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            scanLocked = false
        }
    }

    private var permissionRequestView: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                "Accès caméra requis",
                systemImage: "camera.viewfinder",
                description: Text("Autorisez la caméra pour scanner automatiquement le QR code affiché par votre serveur PVE Center.")
            )
            Button("Autoriser la caméra") {
                Task {
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    cameraPermission = granted ? .authorized : .denied
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.accent(accentTheme, colorScheme))

            Button("Coller un lien manuellement") {
                showManualFallbackSheet = true
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPermission = granted ? .authorized : .denied
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Caméra non autorisée",
                systemImage: "video.slash.fill",
                description: Text("L'accès à la caméra a été refusé. Activez-le dans Réglages ou collez le lien d'appairage manuellement.")
            )

            HStack(spacing: 12) {
                Button("Ouvrir Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Coller un lien") {
                    showManualFallbackSheet = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var noCameraFallbackView: some View {
        VStack(spacing: 12) {
            Label("Caméra indisponible sur cet appareil (Simulateur) — utilisez la saisie ou le collage ci-dessous.", systemImage: "camera.badge.ellipsis")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
            manualEntryBody
        }
    }

    private func handleDetectedCode(_ raw: String) {
        guard !scanLocked else { return }
        if let parsed = Self.parseConnectionInput(raw) {
            scanLocked = true
            parseError = nil
            onConnectPayload(parsed)
            dismiss()
        } else {
            parseError = "QR code non reconnu comme lien PVE Center."
        }
    }
    #endif

    // MARK: - Cross-Platform Manual / Paste Fallback

    private var manualEntryBody: some View {
        #if os(tvOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Connexion par lien d'appairage")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))

                Text("Collez ou saisissez un lien pvecenter://connect?url=... ou l'adresse HTTPS de votre serveur.")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))

                TextField("pvecenter://connect?url=https://...", text: $manualInput)
                    .autocorrectionDisabled()

                if let parseError {
                    Label(parseError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Button {
                    submitManualInput()
                } label: {
                    Label("Valider le lien", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .adaptiveGlassButtonStyle(prominent: true)
                .tint(DesignTokens.accent(accentTheme, colorScheme))
                .disabled(manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(36)
        }
        #else
        Form {
            Section {
                Text("Collez un lien d'appairage généré par le panneau web ou saisissez directement l'URL HTTPS de votre serveur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("pvecenter://connect?url=https://...&name=...", text: $manualInput, axis: .vertical)
                    .lineLimit(2...4)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif

                #if os(iOS) || os(macOS)
                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Coller depuis le presse-papiers", systemImage: "doc.on.clipboard")
                }
                #endif
            } header: {
                Text("Lien ou URL de connexion")
            }

            if let parseError {
                Section {
                    Label(parseError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    submitManualInput()
                } label: {
                    HStack {
                        Spacer()
                        Label("Utiliser ce serveur", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent(accentTheme, colorScheme))
                .disabled(manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        #endif
    }

    #if os(iOS) || os(macOS)
    private func pasteFromClipboard() {
        #if os(iOS)
        if let text = UIPasteboard.general.string {
            manualInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
            parseError = nil
        }
        #elseif os(macOS)
        if let text = NSPasteboard.general.string(forType: .string) {
            manualInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
            parseError = nil
        }
        #endif
    }
    #endif

    private func submitManualInput() {
        guard let parsed = Self.parseConnectionInput(manualInput) else {
            parseError = "Lien invalide. Format attendu : pvecenter://connect?url=https://... ou https://hôte"
            return
        }
        parseError = nil
        onConnectPayload(parsed)
        showManualFallbackSheet = false
        dismiss()
    }
}

#if os(iOS)
private struct QRCameraPreviewRepresentable: UIViewControllerRepresentable {
    let torchEnabled: Bool
    let onCodeDetected: (String) -> Void

    func makeUIViewController(context: Context) -> QRCameraViewController {
        let controller = QRCameraViewController()
        controller.onCodeDetected = onCodeDetected
        return controller
    }

    func updateUIViewController(_ uiViewController: QRCameraViewController, context: Context) {
        uiViewController.onCodeDetected = onCodeDetected
        uiViewController.setTorch(enabled: torchEnabled)
    }
}

@MainActor
private final class QRCameraViewController: UIViewController {
    var onCodeDetected: ((String) -> Void)?

    private let sessionBox = CaptureSessionCoordinator()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let layer = AVCaptureVideoPreviewLayer(session: sessionBox.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        self.previewLayer = layer

        sessionBox.configureIfNeeded { [weak self] code in
            Task { @MainActor [weak self] in
                self?.onCodeDetected?(code)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionBox.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionBox.stop()
        setTorch(enabled: false)
    }

    func setTorch(enabled: Bool) {
        sessionBox.setTorch(enabled: enabled)
    }
}

private final class CaptureSessionCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.ac.pvepanel.qr.capture")
    private var isConfigured = false
    private var onCode: (@Sendable (String) -> Void)?

    func configureIfNeeded(onCode: @escaping @Sendable (String) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.onCode = onCode
            guard !self.isConfigured else { return }

            self.session.beginConfiguration()
            defer {
                self.session.commitConfiguration()
                self.isConfigured = true
            }

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                return
            }
            self.session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard self.session.canAddOutput(output) else { return }
            self.session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: self.queue)
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func setTorch(enabled: Bool) {
        queue.async {
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = enabled ? .on : .off
                device.unlockForConfiguration()
            } catch {
                // Ignore torch errors on devices without flash control.
            }
        }
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              !value.isEmpty else {
            return
        }
        onCode?(value)
    }
}
#endif
