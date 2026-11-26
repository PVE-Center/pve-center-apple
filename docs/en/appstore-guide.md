[English](../en/appstore-guide.md) | [Français](../fr/appstore-guide.md)

# Apple Deployment (iPhone, iPad, Mac & Apple TV) & App Store Guide — PVE Center

**PVE Center** is a **100% native multi-platform Swift 6 & SwiftUI application** (`PVECenter.xcodeproj`) built in line with *Apple Human Interface Guidelines* for **iPhone, iPad, Mac, and Apple TV (`tvOS 27.0`)**, designed to connect to a [**PVE Command Center (`pve-panel`)**](https://github.com/PVE-Center/pve-panel) server.

---

## 1. Multi-Platform Xcode 27 / Swift 6 Project Structure

| Item | Value in Repository |
|---|---|
| **Xcode Project** | `PVECenter.xcodeproj` (Swift 6.0, Xcode 27+ compatibility) |
| **Universal Target** | `PVECenter` (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx appletvos appletvsimulator"`, `TARGETED_DEVICE_FAMILY = "1,2,3"`) |
| **Xcode Schemes** | `PVECenter` (universal iOS / macOS / tvOS) and `PVECenter-iOS` |
| **Deployment Targets** | `IPHONEOS_DEPLOYMENT_TARGET = 27.0`, `MACOSX_DEPLOYMENT_TARGET = 27.0`, `TVOS_DEPLOYMENT_TARGET = 27.0` |
| **Bundle Identifier** | `io.ac.pvepanel.app` *(and `io.github.pvepanel.app` in `scripts/build-macos-app.sh` for SwiftPM macOS bundling)* |
| **SwiftPM Manifest** | `Package.swift` (`swift-tools-version: 6.2`, `.iOS("27.0")`, `.macOS("27.0")`, `.tvOS("27.0")`) |

> **Multi-platform target note:** A single unified target `PVECenter` compiles natively for **iPhone/iPad (`iphoneos` / `iphonesimulator`)**, **Mac (`macosx`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`)**, and **Apple TV (`appletvos` / `appletvsimulator`)** using Bundle ID `io.ac.pvepanel.app`. If you split targets in Xcode, keep `io.ac.pvepanel.app` so `pvecenter://` deep links and APNs remain aligned with the server `config/config.yaml`.

### Native Apple Stack

- **Swift 6 Strict Concurrency & SwiftUI**: `NavigationSplitView` + `MenuBarExtra` on Mac (`⌘R`, `⌘L`, `⌘;`, `⌘1`–`⌘6`), `TabView` + `.sensoryFeedback` on iPhone/iPad, 10-foot UI focus engine on Apple TV (`tvOS 27.0`), adaptive **System / Light / Dark** appearance with 6 Cider accent palettes (`AccentTheme`).
- **Secure Local Persistence**: **SwiftData** (`ServerProfileEntity`, `CachedIncidentEntity`, `CachedCustomServiceEntity`) + **Keychain** (`KeychainStore` via `kSecClassGenericPassword`; API Bearer tokens are never written in plaintext to `UserDefaults`).
- **Discovery & End-to-End Encrypted Pairing**:
  - **Native Bonjour / mDNS** (`BonjourDiscoveryService` via `Network.framework` `NWBrowser` / `NWConnection`) for `_pvecenter._tcp` and LAN scanning (`_http._tcp`, `_ssh._tcp`, `_smb._tcp`).
  - **6-Digit PIN Apple TV Pairing** (`PairingCryptoService`): ephemeral **CryptoKit P-256 ECDH** key exchange → **HKDF-SHA256** derivation bound to the PIN → **AES-256-GCM** encrypted payload over Bonjour (`_pvepair._tcp`) or HTTPS relay (`/api/pairing/sessions`).
- **Real-Time Events & Charts**: `RealtimeEventsClient` (`URLSessionWebSocketTask` on `/api/ws/events` with automatic SSE fallback `/api/events/stream`) and **Swift Charts** (`SectorMark`).

---

## 2. Permissions & `Info.plist` (`PVECenter/Resources/Info.plist`)

All required iOS, macOS, and tvOS keys are pre-configured in [`PVECenter/Resources/Info.plist`](../../PVECenter/Resources/Info.plist):

| `Info.plist` Key | Purpose | Configured Value |
|---|---|---|
| `NSLocalNetworkUsageDescription` | Bonjour LAN discovery & Apple TV pairing | Required on iOS 14+ / tvOS 14+ to authorize `NWBrowser` and `NWListener`. |
| `NSBonjourServices` | Declared mDNS service types | `_pvecenter._tcp`, `_pvepair._tcp`, `_http._tcp`, `_ssh._tcp`, `_smb._tcp` |
| `NSCameraUsageDescription` | `pvecenter://` QR Code scanner | Used by `QRScannerView` (`AVCaptureSession` under `#if os(iOS)`). macOS and tvOS fall back cleanly to paste/input and Bonjour/PIN. |
| `CFBundleURLTypes` | Server pairing deep links | `pvecenter` URL scheme (`pvecenter://connect?url=...&name=...&id=...`). |
| `NSAppTransportSecurity` | Local homelab & Tailscale access | `NSAllowsArbitraryLoads = true`, `NSAllowsLocalNetworking = true` for LAN HTTP IPs, self-signed Proxmox certs, or `*.ts.net`. |
| `ITSAppUsesNonExemptEncryption` | App Store Connect export compliance | `false` (uses standard Apple TLS and exempted ephemeral key exchange). |

---

## 3. Push Notifications (APNs): Free Apple ID vs. Apple Developer Program

### Why `aps-environment` Is NOT Hardcoded in `project.pbxproj`

In [`PVECenter.xcodeproj/project.pbxproj`](../../PVECenter.xcodeproj/project.pbxproj), no `CODE_SIGN_ENTITLEMENTS` file forces `aps-environment` by default:

- **With a free Personal Team Apple ID:** Apple does not permit the *Push Notifications* (`aps-environment`) entitlement on free provisioning profiles. Leaving it out lets **any developer build and install immediately** on Simulators or physical iPhone/iPad/Apple TV devices via Xcode (Automatic Signing) or `./scripts/deploy-device.sh` with zero provisioning errors.
- **Works out-of-the-box without `.p8` or `aps-environment`:**
  - Live **WebSocket / SSE** streaming (`/api/ws/events` and `/api/events/stream`).
  - **Interactive local notifications** via `UNUserNotificationCenter` on iOS, iPadOS, and macOS (`SERVICE_ALERT` category with **`Mute 1h`** (`MUTE_1H`) and **`Tester`** (`TEST_SERVICE`) quick actions).
  - **Live in-app alert banners on Apple TV (`tvOS 27.0`)** via `PushNotificationManager.activeTVBanner` (since tvOS does not support system interactive notification actions).
  - Server-side webhooks (**Discord**, **Telegram**, **Generic Webhook / ntfy / Gotify / Home Assistant**) work 100% independently of Apple Developer membership.

### Enabling Background APNs Push (Paid Apple Developer Program)

Once you have a paid Apple Developer Program account ($99/year) and want remote push notifications when the app is closed:

1. **In Xcode:**
   - Open `PVECenter.xcodeproj` → select the **`PVECenter`** target → **Signing & Capabilities**.
   - Select your **Team** and confirm the Bundle Identifier (`io.ac.pvepanel.app`).
   - Click **`+ Capability`** and add **Push Notifications** *(and **Background Modes → Remote notifications** on iOS if desired)*. Xcode creates an `.entitlements` file containing `aps-environment`.
2. **In Apple Developer Portal:**
   - Go to *Certificates, Identifiers & Profiles → Keys* → click **`+`**.
   - Name the key (e.g., `PVE Center APNs`), check **Apple Push Notifications service (APNs)**, and generate it.
   - Download `AuthKey_<KEY_ID>.p8` *(can only be downloaded once!)* and note your **Key ID** and **Team ID** (*Membership Details*).
3. **On your `pve-panel` server:**
   - Copy the key to `./config/AuthKey.p8` (mounted into Docker at `/app/config/AuthKey.p8` and ignored by `.gitignore`).
   - Configure `notifications.apns` in `config/config.yaml` (or via the Web / Apple *Notifications* settings):
     ```yaml
     notifications:
       apns:
         enabled: true
         team_id: "ABCDE12345"
         key_id: "XYZ1234567"
         bundle_id: "io.ac.pvepanel.app"
         private_key_path: "/app/config/AuthKey.p8"
         use_sandbox: false   # true for Xcode Debug, false for TestFlight / App Store
     ```
4. **Verify:** Launch the app on your device (accept notification permission so the device token registers via `POST /api/notifications/devices`), then trigger a test from **Notifications → Test** (`POST /api/notifications/test`).

---

## 4. Built-in Demo Mode (`DemoDataStore`) & App Store Review (Guideline 2.1)

Because Apple's App Review team cannot reach your private LAN or Tailnet, the app ships with an in-memory `actor DemoDataStore`:

- On first launch with no server configured, the onboarding wizard offers **"Mode Démo"** (also accessible anytime under *Server Settings* → *YAML, Sync & Démo*).
- Every screen works interactively in memory: Proxmox node, VMs/LXC start/stop, storage & SMART health, Swift Charts, custom services (`http_rest`, `tcp_port`, `icmp_ping`, `json_metrics`, `webhook_ingest`), incident timeline (`Acknowledge`, `Mute 1h`), notification webhooks, YAML config editor, LAN scan, and Apple TV PIN pairing.

### Ready-to-Paste App Store Connect Review Notes

> **Demo Mode (No private VPN or homelab required):**
> PVE Center is a native SwiftUI client for self-hosted Proxmox VE & homelab servers (reachable via local Bonjour mDNS or Tailscale Serve). Because private homelab servers are unreachable from outside the owner's LAN/Tailnet, we provide a complete in-memory interactive Demo Mode:
> 1. Launch the app. On the onboarding screen, tap **"Mode Démo"** (or open **Server Settings** → **YAML, Sync & Démo** and enable Demo Mode).
> 2. Explore all tabs (*Overview*, *Proxmox LXC/VM*, *Storage & Swift Charts*, *Services*, *Activity & Incidents*, *Users*) and Settings (*Appearance & Liquid Glass*, *YAML Editor*, *Notifications*, *Apple TV PIN Pairing*).
> 3. Trigger live interactive actions (start/stop VM, test custom services, acknowledge or mute incidents).

---

## 5. Build Scripts, Local Deployment, CI & Sideloading

### Scripts in `scripts/`

| Script | Target | Description |
|---|---|---|
| `./scripts/run-iphone-sim.sh [UDID]` | iOS Simulator | Boots an iPhone simulator (shuts down conflicting Apple TV simulators), builds Debug `iphonesimulator`, installs and launches `io.ac.pvepanel.app`. |
| `./scripts/run-appletv-sim.sh [UDID]` | tvOS Simulator | Boots an Apple TV 4K simulator, builds Debug `appletvsimulator`, installs and launches `io.ac.pvepanel.app`. |
| `./scripts/install-mac.sh` | Native Mac (Xcode) | Builds `PVECenter` for `macosx` (Release, ad-hoc `-` signature) and installs `/Applications/PVE Center.app`. |
| `./scripts/build-macos-app.sh` | Native Mac (SwiftPM) | Runs `swift build -c release`, generates `AppIcon.icns`, ad-hoc signs `build/PVE Center.app` (Bundle ID `io.github.pvepanel.app`), and installs to `/Applications` or `~/Applications`. |
| `./scripts/deploy-device.sh` | Physical Device | Release build and install via `xcrun devicectl` for physical iPhone, iPad, or Apple TV (`--list`, `-t <TEAM_ID>`, `-p ios\|tvos`, `-d <UDID>`). |
| `./scripts/prepare-appstore-secrets.sh` | TestFlight CI | Validates `.p12`, `.mobileprovision`, and `.p8` API keys locally, Base64-encodes them, and optionally uploads all 8 secrets via `gh secret set` (`--apply-gh <OWNER/REPO>`). |

Quick examples:

```bash
# List connected physical Apple devices (USB or paired Wi-Fi)
./scripts/deploy-device.sh --list

# Deploy to physical iPhone / iPad
./scripts/deploy-device.sh -t <YOUR_TEAM_ID> -p ios

# Deploy to physical Apple TV
./scripts/deploy-device.sh -t <YOUR_TEAM_ID> -p tvos -d <APPLE_TV_UDID>

# Verify Swift 6 & unsigned tvOS builds
swift build
xcodebuild -project PVECenter.xcodeproj -scheme PVECenter -destination 'generic/platform=tvOS' -derivedDataPath /tmp/pve-tvos-ci CODE_SIGNING_ALLOWED=NO build
```

### TestFlight & App Store Connect (Local or GitHub Actions)

- **Via Xcode:** Open `PVECenter.xcodeproj`, select `Any iOS Device (arm64)`, `Any Mac`, or `Any tvOS Device`, then run **Product → Archive → Distribute App → TestFlight & App Store**.
- **Via GitHub Actions:**
  - [`.github/workflows/ci-apple.yml`](../../.github/workflows/ci-apple.yml) runs `bash -n scripts/*.sh`, `plutil -lint PVECenter/Resources/Info.plist`, `swift build`, and matrix `xcodebuild` checks for macOS, iOS Simulator, and tvOS Simulator.
  - [`.github/workflows/ios-appstore.yml`](../../.github/workflows/ios-appstore.yml) on `macos-15`:
    1. **`swift-verify`**: runs `./scripts/build-macos-app.sh` and verifies the `generic/platform=tvOS` build (`CODE_SIGNING_ALLOWED=NO`), then uploads `pve-center-macos-app`.
    2. **`build-ios`**: archives `PVECenter.xcodeproj`, signs and exports the `.ipa` when secrets (`APPLE_CERTIFICATE_BASE64`, `APPLE_P12_PASSWORD`, `APPLE_PROVISIONING_PROFILE_BASE64`, `APPLE_PROVISIONING_PROFILE_NAME`, `APPLE_TEAM_ID`) are configured, and uploads to TestFlight when `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, and `APPSTORE_PRIVATE_KEY` are set. Without Apple secrets, it builds an unsigned verification archive.

### Sideloading Without a Paid Account (AltStore / SideStore / Sideloadly)

If you do not have a paid Apple Developer Program account and want to install the app on your personal iPhone or iPad:

1. **Via Xcode + `./scripts/deploy-device.sh`** *(simplest on a Mac)*: enable **Developer Mode** on iPhone (*Settings → Privacy & Security → Developer Mode*), sign into your free Apple ID in Xcode (*Settings → Accounts*), and run `./scripts/deploy-device.sh -p ios`.
2. **Via AltStore / SideStore / Sideloadly (`.ipa`)**:
   - Create an unsigned archive and package `Payload/PVE Center.app` into an `.ipa`:
     ```bash
     xcodebuild -project PVECenter.xcodeproj -scheme PVECenter -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/PVECenter.xcarchive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" clean archive
     mkdir -p /tmp/Payload && cp -R "/tmp/PVECenter.xcarchive/Products/Applications/PVE Center.app" /tmp/Payload/
     (cd /tmp && zip -r PVECenter-unsigned.ipa Payload)
     ```
   - Sideload `/tmp/PVECenter-unsigned.ipa` with **AltStore**, **SideStore** *(supports automatic on-device Wi-Fi refresh after initial setup)*, or **Sideloadly**.
   - **Known Free-Account Limitations (7-Day Expiry):**
     - Personal team provisioning expires every **7 days** (AltServer / SideStore automates background renewal).
     - **Remote APNs is unavailable** on free certificates (`aps-environment` omitted): use Discord / Telegram / ntfy webhooks and in-app WebSocket/SSE alerts.
     - Even when AltStore/SideStore rewrites the Bundle Identifier with a personal team suffix, Bonjour (`_pvecenter._tcp`), QR scanning (`pvecenter://`), Keychain storage, and Apple TV PIN pairing continue to work normally.

### Zero-Certificate Alternative: Safari PWA

Open `https://<hostname>.<tailnet>.ts.net` in **Safari** on iPhone/iPad → **Share** → **Add to Home Screen**.
