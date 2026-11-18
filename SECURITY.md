# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in **PVE Center (Apple)** — such as a flaw in Keychain credential handling, CryptoKit Apple TV pairing (`PairingCryptoService`), URL deep-linking (`pvecenter://`), or TLS/token transmission — **please do not open a public GitHub issue**.

Instead, report it privately via **GitHub Security Advisories** on [`PVE-Center/pve-center-apple`](https://github.com/PVE-Center/pve-center-apple/security/advisories/new) with:

- A clear description of the vulnerability and affected files/platforms
- Steps to reproduce or proof of concept
- Potential impact (e.g., credential disclosure, MITM on pairing, local bypass)

We aim to acknowledge reports within **72 hours** and coordinate a fix before public disclosure.

## Security Architecture Highlights

- **Credential Storage (`KeychainStore.swift`)**: API Bearer tokens, session tokens, onboarding tokens, Proxmox tokens, and pairing secrets are stored in Apple Keychain (`kSecClassGenericPassword`, service `io.ac.pvepanel.app.credentials`) keyed by server profile UUID — never in plaintext `UserDefaults`.
- **Encrypted Apple TV Pairing (`PairingCryptoService.swift`)**: Uses ephemeral **P-256 ECDH** keys (`CryptoKit`), **HKDF-SHA256** key derivation bound to the 6-digit PIN (`pvecenter-pairing-salt-v1:` / `pvecenter-pairing-aes256gcm-v1:`), and **AES-256-GCM** authenticated encryption across both local Bonjour (`_pvepair._tcp`) and the server HTTPS relay.
- **Local Network & Transport (`Info.plist`)**: `NSAppTransportSecurity` sets `NSAllowsLocalNetworking = true` and `NSAllowsArbitraryLoads = true` intentionally to support LAN HTTP servers and self-signed homelab certificates; over Tailscale (`*.ts.net`), TLS HTTPS is used end-to-end.
- **No Secrets in Git**: `.gitignore` excludes `*.p8`, `*.p12`, `*.cer`, and `*.mobileprovision`. CI signing uses GitHub Actions secrets only.
