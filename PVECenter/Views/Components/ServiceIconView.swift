import SwiftUI

public struct ServiceBrandSpec: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let shortLabel: String
    public let aliases: [String]
    public let keywords: [String]
    public let accentHex: UInt32
    public let secondaryHex: UInt32

    public init(
        id: String,
        label: String,
        shortLabel: String? = nil,
        aliases: [String] = [],
        keywords: [String] = [],
        accentHex: UInt32,
        secondaryHex: UInt32
    ) {
        self.id = id
        self.label = label
        self.shortLabel = shortLabel ?? label
        self.aliases = aliases
        self.keywords = keywords
        self.accentHex = accentHex
        self.secondaryHex = secondaryHex
    }
}

public enum ServiceBrandCatalog: Sendable {
    private static let legacyAutoMatchIcons: Set<String> = [
        "", "film", "play", "sparkles", "clapperboard", "tv", "search",
        "download", "cloud", "lock", "gamepad2", "server", "globe",
        "activity", "layoutgrid", "router", "wifi", "database", "cpu",
        "harddrive", "shield", "radar", "terminal", "server.rack",
        "play.tv.fill", "lock.shield.fill", "arrow.down.circle.fill",
    ]

    public static let brands: [ServiceBrandSpec] = [
        ServiceBrandSpec(id: "jellyfin", label: "Jellyfin", aliases: ["jellyfin"], keywords: ["jellyfin"], accentHex: 0xAA5CC3, secondaryHex: 0x00A4DC),
        ServiceBrandSpec(id: "plex", label: "Plex", aliases: ["plex"], keywords: ["plex"], accentHex: 0xE5A00D, secondaryHex: 0xCC7B19),
        ServiceBrandSpec(id: "jellyseerr", label: "Jellyseerr", aliases: ["jellyseerr", "overseerr", "seerr"], keywords: ["jellyseerr", "overseerr", "seerr"], accentHex: 0x6366F1, secondaryHex: 0xA855F7),
        ServiceBrandSpec(id: "radarr", label: "Radarr", aliases: ["radarr"], keywords: ["radarr"], accentHex: 0xF59E0B, secondaryHex: 0xD97706),
        ServiceBrandSpec(id: "sonarr", label: "Sonarr", aliases: ["sonarr"], keywords: ["sonarr"], accentHex: 0x0EA5E9, secondaryHex: 0x00CCFF),
        ServiceBrandSpec(id: "prowlarr", label: "Prowlarr", aliases: ["prowlarr"], keywords: ["prowlarr"], accentHex: 0xF97316, secondaryHex: 0xEA580C),
        ServiceBrandSpec(id: "qbittorrent", label: "qBittorrent", aliases: ["qbittorrent", "qbit"], keywords: ["qbittorrent", "qbit"], accentHex: 0x2563EB, secondaryHex: 0x60A5FA),
        ServiceBrandSpec(id: "nextcloud", label: "Nextcloud", aliases: ["nextcloud"], keywords: ["nextcloud"], accentHex: 0x0082C9, secondaryHex: 0x38BDF8),
        ServiceBrandSpec(id: "vaultwarden", label: "Vaultwarden", aliases: ["vaultwarden", "bitwarden"], keywords: ["vaultwarden", "bitwarden"], accentHex: 0x175DDC, secondaryHex: 0x3B82F6),
        ServiceBrandSpec(id: "pelican", label: "Pelican", aliases: ["pelican", "pterodactyl"], keywords: ["pelican", "pterodactyl", "minecraft"], accentHex: 0x10B981, secondaryHex: 0x06B6D4),
        ServiceBrandSpec(id: "proxmox", label: "Proxmox VE", shortLabel: "Proxmox", aliases: ["proxmox", "pve"], keywords: ["proxmox", "pve"], accentHex: 0xE57000, secondaryHex: 0xFB923C),
        ServiceBrandSpec(id: "zoraxy", label: "Zoraxy", aliases: ["zoraxy", "zoraxy-tunnel"], keywords: ["zoraxy"], accentHex: 0x14B8A6, secondaryHex: 0x38BDF8),
        ServiceBrandSpec(id: "npm", label: "Nginx Proxy Manager", shortLabel: "NPM", aliases: ["npm", "nginx", "nginxproxymanager", "nginx-proxy-manager"], keywords: ["nginx", "proxy manager"], accentHex: 0xF15A24, secondaryHex: 0x14B8A6),
        ServiceBrandSpec(id: "uptime-kuma", label: "Uptime Kuma", shortLabel: "Kuma", aliases: ["uptime-kuma", "uptimekuma", "kuma"], keywords: ["uptime", "kuma"], accentHex: 0x10B981, secondaryHex: 0x5CDD8B),
        ServiceBrandSpec(id: "homepage", label: "Homepage", aliases: ["homepage", "homarr", "dashy"], keywords: ["homepage", "homarr", "dashy"], accentHex: 0x6366F1, secondaryHex: 0x38BDF8),
        ServiceBrandSpec(id: "freebox", label: "Freebox OS", shortLabel: "Freebox", aliases: ["freebox", "freeboxos"], keywords: ["freebox"], accentHex: 0xE11D48, secondaryHex: 0xFB7185),
        ServiceBrandSpec(id: "adguard", label: "AdGuard Home", shortLabel: "AdGuard", aliases: ["adguard", "adguardhome", "adguard-home"], keywords: ["adguard"], accentHex: 0x67B279, secondaryHex: 0x22C55E),
        ServiceBrandSpec(id: "pihole", label: "Pi-hole", aliases: ["pihole", "pi-hole"], keywords: ["pihole", "pi-hole"], accentHex: 0xEF4444, secondaryHex: 0x22C55E),
        ServiceBrandSpec(id: "home-assistant", label: "Home Assistant", shortLabel: "HASS", aliases: ["home-assistant", "homeassistant", "hass"], keywords: ["home assistant", "home-assistant", "hass"], accentHex: 0x18BCF2, secondaryHex: 0x0EA5E9),
        ServiceBrandSpec(id: "grafana", label: "Grafana", aliases: ["grafana", "prometheus"], keywords: ["grafana"], accentHex: 0xF46800, secondaryHex: 0xF59E0B),
        ServiceBrandSpec(id: "tailscale", label: "Tailscale", aliases: ["tailscale", "headscale"], keywords: ["tailscale", "headscale"], accentHex: 0x38BDF8, secondaryHex: 0x64748B),
        ServiceBrandSpec(id: "cloudflare", label: "Cloudflare", aliases: ["cloudflare", "cloudflared"], keywords: ["cloudflare", "tunnel"], accentHex: 0xF38020, secondaryHex: 0xFDBA74),
        ServiceBrandSpec(id: "docker", label: "Docker", aliases: ["docker"], keywords: ["docker", "compose"], accentHex: 0x2496ED, secondaryHex: 0x38BDF8),
        ServiceBrandSpec(id: "portainer", label: "Portainer", aliases: ["portainer"], keywords: ["portainer"], accentHex: 0x13BEF9, secondaryHex: 0x0284C7),
        ServiceBrandSpec(id: "immich", label: "Immich", aliases: ["immich"], keywords: ["immich"], accentHex: 0xF43F5E, secondaryHex: 0x6366F1),
        ServiceBrandSpec(id: "traefik", label: "Traefik", aliases: ["traefik"], keywords: ["traefik"], accentHex: 0x24A1C1, secondaryHex: 0x06B6D4),
        ServiceBrandSpec(id: "authentik", label: "Authentik", aliases: ["authentik", "authelia"], keywords: ["authentik", "authelia", "sso"], accentHex: 0xFD4B2D, secondaryHex: 0xFB923C),
        ServiceBrandSpec(id: "gitea", label: "Gitea", aliases: ["gitea", "forgejo", "gitlab"], keywords: ["gitea", "forgejo", "gitlab"], accentHex: 0x609926, secondaryHex: 0x84CC16),
    ]

    public static func resolveBrand(
        icon: String?,
        serviceId: String? = nil,
        serviceName: String? = nil,
        widget: String? = nil
    ) -> ServiceBrandSpec? {
        let raw = (icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        if lower.hasPrefix("sf:") || lower.hasPrefix("lucide:") {
            return nil
        }

        if let direct = brands.first(where: { $0.id == lower || $0.aliases.contains(lower) }) {
            return direct
        }

        if legacyAutoMatchIcons.contains(lower) {
            let haystack = "\(serviceId ?? "") \(widget ?? "") \(serviceName ?? "")".lowercased()
            if !haystack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                for brand in brands where brand.keywords.contains(where: { haystack.contains($0) }) {
                    return brand
                }
            }
        }
        return nil
    }

    public static func cleanGenericIconName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("sf:") {
            return String(trimmed.dropFirst(3))
        }
        if trimmed.lowercased().hasPrefix("lucide:") {
            return String(trimmed.dropFirst(7))
        }
        return trimmed
    }

    public static func displayLabel(
        icon: String?,
        serviceId: String? = nil,
        serviceName: String? = nil,
        widget: String? = nil
    ) -> String {
        if let brand = resolveBrand(icon: icon, serviceId: serviceId, serviceName: serviceName, widget: widget) {
            return brand.label
        }
        let cleaned = cleanGenericIconName(icon ?? "")
        return cleaned.isEmpty ? "Serveur" : cleaned
    }
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

public struct ServiceIconView: View {
    public let icon: String?
    public let serviceId: String?
    public let serviceName: String?
    public let widget: String?
    public let isOnline: Bool
    public let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    public init(
        icon: String?,
        serviceId: String? = nil,
        serviceName: String? = nil,
        widget: String? = nil,
        isOnline: Bool = true,
        size: CGFloat = 40
    ) {
        self.icon = icon
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.widget = widget
        self.isOnline = isOnline
        self.size = size
    }

    public var body: some View {
        let radius = max(8, size * 0.26)

        if let brand = ServiceBrandCatalog.resolveBrand(
            icon: icon,
            serviceId: serviceId,
            serviceName: serviceName,
            widget: widget
        ) {
            let primary = Color(hex: brand.accentHex)
            let secondary = Color(hex: brand.secondaryHex)

            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                primary.opacity(colorScheme == .light ? 0.16 : 0.24),
                                secondary.opacity(colorScheme == .light ? 0.12 : 0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                brandGlyph(for: brand, primary: primary, secondary: secondary)
                    .frame(width: size * 0.56, height: size * 0.56)
            }
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        (isOnline ? primary : DesignTokens.critical(colorScheme)).opacity(0.35),
                        lineWidth: 0.9
                    )
            )
            .opacity(isOnline ? 1.0 : 0.72)
        } else {
            let symbolName = ServiceSymbolCatalog.resolveSFSymbol(
                ServiceBrandCatalog.cleanGenericIconName(icon ?? "")
            )
            let fallbackColor = isOnline ? DesignTokens.accent(accentTheme, colorScheme) : DesignTokens.critical(colorScheme)

            Image(systemName: symbolName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(fallbackColor)
                .frame(width: size, height: size)
                .background(
                    DesignTokens.surfaceElevated(theme: accentTheme, colorScheme),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
        }
    }

    @ViewBuilder
    private func brandGlyph(for brand: ServiceBrandSpec, primary: Color, secondary: Color) -> some View {
        switch brand.id {
        case "jellyfin":
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.5, y: h * 0.06))
                        p.addQuadCurve(to: CGPoint(x: w * 0.92, y: h * 0.78), control: CGPoint(x: w * 0.85, y: h * 0.42))
                        p.addQuadCurve(to: CGPoint(x: w * 0.08, y: h * 0.78), control: CGPoint(x: w * 0.5, y: h * 0.98))
                        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.06), control: CGPoint(x: w * 0.15, y: h * 0.42))
                    }
                    .fill(LinearGradient(colors: [primary, secondary], startPoint: .top, endPoint: .bottom))

                    Path { p in
                        p.move(to: CGPoint(x: w * 0.5, y: h * 0.34))
                        p.addQuadCurve(to: CGPoint(x: w * 0.68, y: h * 0.68), control: CGPoint(x: w * 0.65, y: h * 0.5))
                        p.addQuadCurve(to: CGPoint(x: w * 0.32, y: h * 0.68), control: CGPoint(x: w * 0.5, y: h * 0.76))
                        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.34), control: CGPoint(x: w * 0.35, y: h * 0.5))
                    }
                    .fill(Color.black.opacity(0.42))
                }
            }

        case "plex":
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { p in
                    p.move(to: CGPoint(x: w * 0.22, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.50))
                    p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.88))
                    p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.88))
                    p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.50))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
            }

        case "jellyseerr":
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))

        case "radarr":
            Image(systemName: "film.circle.fill")
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))

        case "sonarr":
            Image(systemName: "tv.and.hifispeaker.fill")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [secondary, primary], startPoint: .topLeading, endPoint: .bottomTrailing))

        case "prowlarr":
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))

        case "qbittorrent":
            Text("qB")
                .font(.system(size: size * 0.38, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Circle().fill(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                )

        case "nextcloud":
            HStack(spacing: -size * 0.04) {
                Circle().strokeBorder(.white, lineWidth: max(1.3, size * 0.055))
                    .frame(width: size * 0.16, height: size * 0.16)
                Circle().strokeBorder(.white, lineWidth: max(1.6, size * 0.065))
                    .frame(width: size * 0.25, height: size * 0.25)
                Circle().strokeBorder(.white, lineWidth: max(1.3, size * 0.055))
                    .frame(width: size * 0.16, height: size * 0.16)
            }
            .padding(size * 0.06)
            .background(
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .fill(primary)
            )

        case "vaultwarden":
            ZStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: size * 0.50, weight: .bold))
                    .foregroundStyle(primary)
            }

        case "pelican":
            Image(systemName: "bird.fill")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))

        case "proxmox":
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { p in
                    p.move(to: CGPoint(x: w * 0.18, y: h * 0.18))
                    p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.50))
                    p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.82))
                    p.move(to: CGPoint(x: w * 0.82, y: h * 0.18))
                    p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.50))
                    p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.82))
                }
                .stroke(primary, style: StrokeStyle(lineWidth: max(2.2, size * 0.095), lineCap: .round, lineJoin: .round))
            }

        case "zoraxy":
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { p in
                    p.move(to: CGPoint(x: w * 0.18, y: h * 0.22))
                    p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.22))
                    p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.78))
                    p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.78))
                }
                .stroke(
                    LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: max(2.2, size * 0.09), lineCap: .round, lineJoin: .round)
                )
            }

        case "npm":
            ZStack {
                Image(systemName: "hexagon.fill")
                    .font(.system(size: size * 0.52))
                    .foregroundStyle(secondary.opacity(0.25))
                Text("N")
                    .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                    .foregroundStyle(primary)
            }

        case "uptime-kuma":
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Circle().fill(primary))

        case "homepage":
            let tile = size * 0.22
            VStack(spacing: size * 0.06) {
                HStack(spacing: size * 0.06) {
                    RoundedRectangle(cornerRadius: size * 0.06).fill(primary).frame(width: tile, height: tile)
                    RoundedRectangle(cornerRadius: size * 0.06).fill(secondary).frame(width: tile, height: tile)
                }
                HStack(spacing: size * 0.06) {
                    RoundedRectangle(cornerRadius: size * 0.06).fill(secondary).frame(width: tile, height: tile)
                    RoundedRectangle(cornerRadius: size * 0.06).fill(primary.opacity(0.85)).frame(width: tile, height: tile)
                }
            }

        case "freebox":
            Text("f")
                .font(.system(size: size * 0.46, weight: .heavy, design: .serif))
                .italic()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.16, style: .continuous).fill(primary)
                )

        case "adguard":
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(primary)

        case "pihole":
            Image(systemName: "shield.fill")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(primary)

        case "home-assistant":
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(primary)

        case "grafana":
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))

        case "tailscale":
            let dotSize = size * 0.11
            VStack(spacing: size * 0.06) {
                HStack(spacing: size * 0.06) {
                    Circle().fill(secondary).frame(width: dotSize, height: dotSize)
                    Circle().fill(secondary).frame(width: dotSize, height: dotSize)
                    Circle().fill(secondary).frame(width: dotSize, height: dotSize)
                }
                HStack(spacing: size * 0.06) {
                    Circle().fill(primary).frame(width: dotSize, height: dotSize)
                    Circle().fill(primary).frame(width: dotSize, height: dotSize)
                    Circle().fill(primary).frame(width: dotSize, height: dotSize)
                }
                HStack(spacing: size * 0.06) {
                    Circle().fill(secondary).frame(width: dotSize, height: dotSize)
                    Circle().fill(primary).frame(width: dotSize, height: dotSize)
                    Circle().fill(secondary).frame(width: dotSize, height: dotSize)
                }
            }

        case "cloudflare":
            Image(systemName: "cloud.fill")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [primary, secondary], startPoint: .leading, endPoint: .trailing))

        case "docker":
            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))

        case "portainer":
            Image(systemName: "helm")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(primary)

        case "immich":
            Image(systemName: "camera.aperture")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [primary, .orange, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))

        case "traefik":
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(primary)

        case "authentik":
            Image(systemName: "key.fill")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(primary)

        case "gitea":
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(primary)

        default:
            Image(systemName: "server.rack")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(primary)
        }
    }
}

public struct ServiceIconPickerSection: View {
    @Binding public var selectedIcon: String
    public let serviceId: String?
    public let serviceName: String?
    public let widget: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    public init(
        selectedIcon: Binding<String>,
        serviceId: String? = nil,
        serviceName: String? = nil,
        widget: String? = nil
    ) {
        self._selectedIcon = selectedIcon
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.widget = widget
    }

    private var gridColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 132), spacing: 14)]
        #else
        return [GridItem(.adaptive(minimum: 64), spacing: 8)]
        #endif
    }

    private var symbolColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 92), spacing: 14)]
        #else
        return [GridItem(.adaptive(minimum: 42), spacing: 8)]
        #endif
    }

    public var body: some View {
        #if os(tvOS)
        GlassCard(padding: 24, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Icône de l'application")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                pickerContent
            }
        }
        #else
        Section("Icône de l'application") {
            pickerContent
        }
        #endif
    }

    @ViewBuilder
    private var pickerContent: some View {
        let activeBrand = ServiceBrandCatalog.resolveBrand(
            icon: selectedIcon,
            serviceId: serviceId,
            serviceName: serviceName,
            widget: widget
        )

        HStack(spacing: 14) {
            ServiceIconView(
                icon: selectedIcon,
                serviceId: serviceId,
                serviceName: serviceName,
                widget: widget,
                isOnline: true,
                size: {
                    #if os(tvOS)
                    56
                    #else
                    44
                    #endif
                }()
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    ServiceBrandCatalog.displayLabel(
                        icon: selectedIcon,
                        serviceId: serviceId,
                        serviceName: serviceName,
                        widget: widget
                    )
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.primaryText(colorScheme))

                Text("Choisissez une icône dédiée Homelab ou un symbole générique")
                    #if os(tvOS)
                    .font(.caption)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    .lineLimit(1)
            }
        }

        LazyVGrid(columns: gridColumns, spacing: {
            #if os(tvOS)
            14
            #else
            8
            #endif
        }()) {
            ForEach(ServiceBrandCatalog.brands) { brand in
                let isSelected = activeBrand?.id == brand.id
                Button {
                    selectedIcon = brand.id
                } label: {
                    VStack(spacing: 6) {
                        ServiceIconView(icon: brand.id, size: {
                            #if os(tvOS)
                            42
                            #else
                            32
                            #endif
                        }())
                        Text(brand.shortLabel)
                            #if os(tvOS)
                            .font(.caption.weight(.medium))
                            #else
                            .font(.system(size: 10, weight: .medium))
                            #endif
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    #if os(tvOS)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    #else
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .background(
                        isSelected
                            ? DesignTokens.accent(accentTheme, colorScheme).opacity(0.18)
                            : DesignTokens.surfaceElevated(theme: accentTheme, colorScheme),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? DesignTokens.accent(accentTheme, colorScheme) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    #endif
                }
                .adaptiveIconTileButtonStyle(
                    isSelected: isSelected,
                    accent: DesignTokens.accent(accentTheme, colorScheme),
                    cornerRadius: 12
                )
                .accessibilityLabel(brand.label)
            }
        }
        .padding(.vertical, 6)

        LazyVGrid(columns: symbolColumns, spacing: {
            #if os(tvOS)
            14
            #else
            8
            #endif
        }()) {
            ForEach(ServiceSymbolCatalog.options) { option in
                let cleaned = ServiceBrandCatalog.cleanGenericIconName(selectedIcon)
                let isSelected = activeBrand == nil && ServiceSymbolCatalog.resolveSFSymbol(cleaned) == option.symbol
                Button {
                    selectedIcon = "sf:\(option.symbol)"
                } label: {
                    Image(systemName: option.symbol)
                        #if os(tvOS)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        #else
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        #endif
                        .foregroundStyle(isSelected ? DesignTokens.accent(accentTheme, colorScheme) : .primary)
                        #if !os(tvOS)
                        .background(
                            isSelected
                                ? DesignTokens.accent(accentTheme, colorScheme).opacity(0.18)
                                : DesignTokens.surfaceElevated(theme: accentTheme, colorScheme),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    isSelected ? DesignTokens.accent(accentTheme, colorScheme) : Color.clear,
                                    lineWidth: 1.4
                                )
                        )
                        #endif
                }
                .adaptiveIconTileButtonStyle(
                    isSelected: isSelected,
                    accent: DesignTokens.accent(accentTheme, colorScheme),
                    cornerRadius: 12
                )
                .accessibilityLabel(option.label)
            }
        }
        .padding(.vertical, 6)

        TextField("Nom personnalisé ou SF Symbol (ex: zoraxy, sf:server.rack)", text: $selectedIcon)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }
}
