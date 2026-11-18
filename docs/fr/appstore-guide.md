[English](../en/appstore-guide.md) | [Français](../fr/appstore-guide.md)

# Déploiement Apple (iPhone, iPad, Mac & Apple TV) & App Store — PVE Center

**PVE Center** est une **application Apple 100 % native multi-plateformes en Swift 6 & SwiftUI** (`PVECenter.xcodeproj`) conçue selon les *Apple Human Interface Guidelines* pour **iPhone, iPad, Mac et Apple TV (`tvOS 27.0`)**, pilotant un serveur [**PVE Command Center (`pve-panel`)**](https://github.com/Fairy-Jeux/pve-panel).

---

## 1. Architecture Xcode 27 / Swift 6 Multi-Plateformes

| Élément | Valeur réelle dans le dépôt |
|---|---|
| **Projet Xcode** | `PVECenter.xcodeproj` (Swift 6.0, compatibilité Xcode 27+) |
| **Cible universelle** | `PVECenter` (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx appletvos appletvsimulator"`, `TARGETED_DEVICE_FAMILY = "1,2,3"`) |
| **Schémas Xcode** | `PVECenter` (universel iOS / macOS / tvOS) et `PVECenter-iOS` |
| **Cibles de déploiement** | `IPHONEOS_DEPLOYMENT_TARGET = 27.0`, `MACOSX_DEPLOYMENT_TARGET = 27.0`, `TVOS_DEPLOYMENT_TARGET = 27.0` |
| **Bundle Identifier** | `io.ac.pvepanel.app` *(et `io.github.pvepanel.app` dans `scripts/build-macos-app.sh` pour l'assemblage SwiftPM)* |
| **Package SwiftPM** | `Package.swift` (`swift-tools-version: 6.2`, `.iOS("27.0")`, `.macOS("27.0")`, `.tvOS("27.0")`) |

> **Note sur les cibles multi-plateformes :** Le projet utilise une cible native unifiée `PVECenter` qui compile pour **iPhone/iPad (`iphoneos` / `iphonesimulator`)**, **Mac (`macosx`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`)** et **Apple TV (`appletvos` / `appletvsimulator`)** avec le même Bundle ID `io.ac.pvepanel.app`. Si vous créez des cibles séparées dans Xcode, conservez `io.ac.pvepanel.app` afin que le deep-link `pvecenter://` et APNs restent alignés avec le serveur `config/config.yaml`.

### Stack technique Apple native

- **Swift 6 strict concurrency & SwiftUI** : `NavigationSplitView` + `MenuBarExtra` sur Mac (`⌘R`, `⌘L`, `⌘;`, `⌘1`–`⌘6`), `TabView` + `.sensoryFeedback` sur iPhone/iPad, 10-foot UI focus engine sur Apple TV (`tvOS 27.0`), thème **Système / Clair / Sombre** adaptatif avec 6 palettes Cider (`AccentTheme`).
- **Persistance locale sécurisée** : **SwiftData** (`ServerProfileEntity`, `CachedIncidentEntity`, `CachedCustomServiceEntity`) + **Keychain** (`KeychainStore` via `kSecClassGenericPassword`, sans jamais stocker les Bearer tokens en clair dans `UserDefaults`).
- **Découverte & Appairage chiffré** :
  - **Bonjour / mDNS natif** (`BonjourDiscoveryService` via `Network.framework` `NWBrowser` / `NWConnection`) pour `_pvecenter._tcp` et scan LAN (`_http._tcp`, `_ssh._tcp`, `_smb._tcp`).
  - **Appairage Apple TV par code PIN à 6 chiffres** (`PairingCryptoService`) : échange de clés éphémères **CryptoKit P-256 ECDH** → dérivation **HKDF-SHA256** liée au PIN → chiffrement **AES-256-GCM** via Bonjour (`_pvepair._tcp`) ou le relais HTTPS `/api/pairing/sessions`.
- **Temps réel & Graphiques** : `RealtimeEventsClient` (`URLSessionWebSocketTask` sur `/api/ws/events` + bascule automatique SSE `/api/events/stream`) et **Swift Charts** (`SectorMark`).

---

## 2. Permissions & `Info.plist` (`PVECenter/Resources/Info.plist`)

Toutes les clés requises par iOS, macOS et tvOS sont déjà configurées dans [`PVECenter/Resources/Info.plist`](../../PVECenter/Resources/Info.plist) :

| Clé `Info.plist` | Rôle | Détails configurés |
|---|---|---|
| `NSLocalNetworkUsageDescription` | Découverte LAN Bonjour & appairage Apple TV | Obligatoire depuis iOS 14+ / tvOS 14+ pour autoriser `NWBrowser` et `NWListener`. |
| `NSBonjourServices` | Types mDNS déclarés auprès d'iOS/tvOS | `_pvecenter._tcp`, `_pvepair._tcp`, `_http._tcp`, `_ssh._tcp`, `_smb._tcp` |
| `NSCameraUsageDescription` | Scanner de QR Code `pvecenter://` | Utilisé par `QRScannerView` (`AVCaptureSession` sous `#if os(iOS)`). macOS et tvOS basculent vers la saisie/collage et Bonjour/PIN. |
| `CFBundleURLTypes` | Deep-linking d'appairage serveur | Schéma `pvecenter` (`pvecenter://connect?url=...&name=...&id=...`). |
| `NSAppTransportSecurity` | Connexions homelab locales & Tailscale | `NSAllowsArbitraryLoads = true`, `NSAllowsLocalNetworking = true` pour joindre les IP LAN HTTP, certificats auto-signés Proxmox ou `*.ts.net`. |
| `ITSAppUsesNonExemptEncryption` | Déclaration export App Store Connect | `false` (TLS Apple standard et échange éphémère exemptés). |

---

## 3. Notifications Push (APNs) : Compte Apple gratuit vs Apple Developer Program

### Pourquoi `aps-environment` n'est PAS forcé dans `project.pbxproj`

Dans [`PVECenter.xcodeproj/project.pbxproj`](../../PVECenter.xcodeproj/project.pbxproj), aucun fichier `CODE_SIGN_ENTITLEMENTS` imposant `aps-environment` n'est forcé par défaut :

- **Avec un compte Apple personnel gratuit (Personal Team) :** Apple n'autorise pas la capability *Push Notifications* (`aps-environment`) sur les profils gratuits. Ne pas forcer cet entitlement permet à **n'importe quel développeur de compiler et installer l'application immédiatement** sur simulateur ou iPhone/iPad/Apple TV physique via Xcode (Signature Automatique) ou `./scripts/deploy-device.sh`, sans erreur de provisioning.
- **Fonctionnement immédiat sans `.p8` ni `aps-environment` :**
  - Connexion temps réel **WebSocket / SSE** (`/api/ws/events` et `/api/events/stream`).
  - **Notifications locales interactives** via `UNUserNotificationCenter` sur iOS, iPadOS et macOS (catégorie `SERVICE_ALERT` avec actions rapides **`Mute 1h`** (`MUTE_1H`) et **`Tester`** (`TEST_SERVICE`)).
  - **Bannières d'alerte temps réel sur Apple TV (`tvOS 27.0`)** via la file `PushNotificationManager.activeTVBanner` (tvOS ne supporte pas les actions de notification système, l'affichage in-app reste actif en direct).
  - Webhooks serveur (**Discord**, **Telegram**, **Webhook générique / ntfy / Gotify / Home Assistant**) 100 % fonctionnels sans compte Apple payant.

### Activer les notifications Push APNs en arrière-plan (Compte Apple Developer Program payant)

Lorsque vous disposez d'un compte Apple Developer Program (99 $/an) et souhaitez recevoir les notifications même lorsque l'app est fermée :

1. **Dans Xcode :**
   - Ouvrez `PVECenter.xcodeproj` → sélectionnez la cible **`PVECenter`** → onglet **Signing & Capabilities**.
   - Sélectionnez votre **Team** et vérifiez le Bundle Identifier (`io.ac.pvepanel.app`).
   - Cliquez sur **`+ Capability`** et ajoutez **Push Notifications** *(et **Background Modes → Remote notifications** pour iOS si souhaité)*. Xcode générera le `.entitlements` contenant `aps-environment`.
2. **Sur le portail Apple Developer :**
   - Allez dans *Certificates, Identifiers & Profiles → Keys* → cliquez sur **`+`**.
   - Donnez un nom (ex. `PVE Center APNs`), cochez **Apple Push Notifications service (APNs)** et générez la clé.
   - Téléchargez le fichier `AuthKey_<KEY_ID>.p8` *(téléchargeable une seule fois !)* et notez votre **Key ID** ainsi que votre **Team ID** (*Membership Details*).
3. **Sur votre serveur PVE Command Center (`pve-panel`) :**
   - Copiez le fichier dans `./config/AuthKey.p8` (monté dans Docker à `/app/config/AuthKey.p8` et ignoré par `.gitignore`).
   - Configurez `notifications.apns` dans `config/config.yaml` (ou depuis l'interface Web / Apple *Notifications*) :
     ```yaml
     notifications:
       apns:
         enabled: true
         team_id: "ABCDE12345"
         key_id: "XYZ1234567"
         bundle_id: "io.ac.pvepanel.app"
         private_key_path: "/app/config/AuthKey.p8"
         use_sandbox: false   # true pour Xcode Debug, false pour TestFlight / App Store
     ```
4. **Tester :** ouvrez l'app sur votre appareil (acceptez l'autorisation de notifications pour enregistrer le token via `POST /api/notifications/devices`), puis lancez un test depuis **Notifications → Tester** (`POST /api/notifications/test`).

---

## 4. Mode Démo natif (`DemoDataStore`) & App Store Review (Guideline 2.1)

L'équipe de révision Apple ne pouvant pas accéder à votre réseau local ou Tailnet privé, l'application embarque `actor DemoDataStore` en mémoire :

- Au premier lancement sans serveur configuré, l'assistant d'onboarding s'ouvre et propose l'option **« Mode Démo »** (également accessible à tout moment via *Serveurs & Tailscale* / *YAML, Sync & Démo*).
- Toutes les vues sont interactives en mémoire : nœud & VMs/LXC Proxmox, stockage & SMART, graphiques Swift Charts, services personnalisés (`http_rest`, `tcp_port`, `icmp_ping`, `json_metrics`, `webhook_ingest`), timeline d'incidents (`Acquitter`, `Mute 1h`), webhooks de notifications, éditeur YAML, scan LAN et appairage Apple TV.

### Notes prêtes pour App Store Connect (`App Review Information`)

> **Demo Mode (No private VPN or homelab required):**
> PVE Center is a native SwiftUI client for self-hosted Proxmox VE & homelab servers (reachable via local Bonjour mDNS or Tailscale Serve). Because private homelab servers are unreachable from outside the owner's LAN/Tailnet, we provide a complete in-memory interactive Demo Mode:
> 1. Launch the app. On the onboarding screen, tap **"Mode Démo"** (or open **"Serveur"** → **"YAML, Sync & Démo"** and activate Demo Mode).
> 2. Explore all tabs (*Poste*, *Machines*, *Stockage*, *Services*, *Activité*, *Comptes*) and Settings (*Apparence & Verre*, *YAML Editor*, *Notifications*, *Apple TV PIN Pairing*).
> 3. Trigger live interactive actions (start/stop VM, test custom services, acknowledge or mute incidents).

---

## 5. Scripts de build, déploiement local, CI & Sideloading

### Scripts fournis dans `scripts/`

| Script | Usage | Description |
|---|---|---|
| `./scripts/run-iphone-sim.sh [UDID]` | Simulateur iOS | Démarre un simulateur iPhone (coupe les simulateurs Apple TV actifs), compile en Debug `iphonesimulator`, installe et lance `io.ac.pvepanel.app`. |
| `./scripts/run-appletv-sim.sh [UDID]` | Simulateur tvOS | Démarre un simulateur Apple TV 4K, compile en Debug `appletvsimulator`, installe et lance `io.ac.pvepanel.app`. |
| `./scripts/install-mac.sh` | Mac natif (Xcode) | Compile la cible `PVECenter` pour `macosx` (Release, signature ad-hoc `-`) et installe `/Applications/PVE Center.app`. |
| `./scripts/build-macos-app.sh` | Mac natif (SwiftPM) | Compile via `swift build -c release`, génère `AppIcon.icns`, signe `build/PVE Center.app` (Bundle ID `io.github.pvepanel.app`) et installe dans `/Applications` ou `~/Applications`. |
| `./scripts/deploy-device.sh` | Appareil physique | Déploie en Release via `xcrun devicectl` sur iPhone, iPad ou Apple TV physique (`--list`, `-t <TEAM_ID>`, `-p ios\|tvos`, `-d <UDID>`). |

Exemples rapides :

```bash
# Lister les appareils physiques connectés (USB ou Wi-Fi jumelé)
./scripts/deploy-device.sh --list

# Déployer sur iPhone/iPad physique
./scripts/deploy-device.sh -t <VOTRE_TEAM_ID> -p ios

# Déployer sur Apple TV physique
./scripts/deploy-device.sh -t <VOTRE_TEAM_ID> -p tvos -d <UDID_APPLE_TV>

# Vérifier la compilation Swift 6 & tvOS sans signature
swift build
xcodebuild -project PVECenter.xcodeproj -scheme PVECenter -destination 'generic/platform=tvOS' -derivedDataPath /tmp/pve-tvos-ci CODE_SIGNING_ALLOWED=NO build
```

### TestFlight & App Store Connect (Local ou GitHub Actions)

- **Via Xcode :** ouvrez `PVECenter.xcodeproj`, choisissez la destination (`Any iOS Device (arm64)`, `Any Mac` ou `Any tvOS Device`), puis **Product → Archive → Distribute App → TestFlight & App Store**.
- **Via GitHub Actions :**
  - [`.github/workflows/ci-apple.yml`](../../.github/workflows/ci-apple.yml) vérifie `bash -n scripts/*.sh`, `plutil -lint PVECenter/Resources/Info.plist`, `swift build` et les cibles Xcode macOS, iOS Simulator et tvOS Simulator.
  - [`.github/workflows/ios-appstore.yml`](../../.github/workflows/ios-appstore.yml) sur `macos-15` :
    1. **`swift-verify`** : exécute `./scripts/build-macos-app.sh` et vérifie le build `generic/platform=tvOS` (`CODE_SIGNING_ALLOWED=NO`), puis publie l'artefact `pve-center-macos-app`.
    2. **`build-ios`** : archive `PVECenter.xcodeproj`, signe et exporte le `.ipa` si les secrets (`APPLE_CERTIFICATE_BASE64`, `APPLE_P12_PASSWORD`, `APPLE_PROVISIONING_PROFILE_BASE64`, `APPLE_PROVISIONING_PROFILE_NAME`, `APPLE_TEAM_ID`) sont configurés, et envoie vers TestFlight si `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID` et `APPSTORE_PRIVATE_KEY` sont renseignés. Sans secrets Apple, il génère une archive de vérification non signée.

### Sideloading sans compte payant (AltStore / SideStore / Sideloadly)

Si vous ne disposez pas d'un compte Apple Developer Program payant et souhaitez installer l'app sur votre iPhone/iPad pour un usage personnel :

1. **Via Xcode + `./scripts/deploy-device.sh`** *(méthode la plus directe depuis Mac)* : activez le **Mode développeur** sur iPhone (*Réglages → Confidentialité et sécurité → Mode développeur*), connectez votre compte Apple gratuit dans Xcode (*Settings → Accounts*), puis exécutez `./scripts/deploy-device.sh -p ios`.
2. **Via AltStore / SideStore / Sideloadly (`.ipa`)** :
   - Générez une archive sans signature puis empaquetez `Payload/PVE Center.app` en `.ipa` :
     ```bash
     xcodebuild -project PVECenter.xcodeproj -scheme PVECenter -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/PVECenter.xcarchive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" clean archive
     mkdir -p /tmp/Payload && cp -R "/tmp/PVECenter.xcarchive/Products/Applications/PVE Center.app" /tmp/Payload/
     (cd /tmp && zip -r PVECenter-unsigned.ipa Payload)
     ```
   - Importez `/tmp/PVECenter-unsigned.ipa` dans **AltStore**, **SideStore** *(renouvellement automatique en Wi-Fi sans PC/Mac après installation initiale !)* ou **Sideloadly**.
   - **Limitations connues des comptes gratuits (7 jours) :**
     - La signature expire tous les **7 jours** (SideStore / AltServer automatise le rafraîchissement en arrière-plan).
     - **APNs distant désactivé** par Apple sur les certificats gratuits (`aps-environment` absent) : conservez Discord / Telegram / ntfy et les alertes WebSocket/SSE temps réel.
     - Si AltStore/SideStore réécrit le Bundle Identifier avec un suffixe d'équipe personnelle, Bonjour (`_pvecenter._tcp`), le scan QR (`pvecenter://`), le Keychain et l'appairage Apple TV par PIN continuent de fonctionner normalement.

### Alternative zéro-certificat : PWA Safari

Ouvrez `https://<hostname>.<tailnet>.ts.net` dans **Safari** sur iPhone/iPad → **Partager** → **Sur l'écran d'accueil**.
