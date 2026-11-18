# Contributing to PVE Center (Apple)

Thank you for helping improve **PVE Center** on iPhone, iPad, Mac, and Apple TV!

## Development Workflow

1. **Fork & Branch**: Fork the repository and create a topic branch from `main` (e.g. `feat/tvos-shortcut` or `fix/bonjour-timeout`).
2. **Code Style & Swift 6 Concurrency**:
   - Follow `.editorconfig` conventions (UTF-8, LF, 4-space indentation for Swift and Shell, 2-space for YAML/JSON).
   - Keep Swift 6 strict concurrency clean (`Sendable`, `@MainActor`, `actor` isolation) with zero new warnings.
   - Maintain cross-platform compilation across `#if os(iOS)`, `#if os(macOS)`, and `#if os(tvOS)`.
   - Never hardcode personal URLs, API tokens, Apple Team IDs, `.p8` keys, or `.mobileprovision` files.
3. **Verify Before Opening a PR**:
   ```bash
   swift build
   bash -n scripts/*.sh
   plutil -lint PVECenter/Resources/Info.plist
   xcodebuild -project PVECenter.xcodeproj -scheme PVECenter -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
   xcodebuild -project PVECenter.xcodeproj -scheme PVECenter-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
   xcodebuild -project PVECenter.xcodeproj -scheme PVECenter -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build
   ```
4. **UI & Accessibility Checklist**:
   - Test both Light and Dark appearances on iPhone/macOS (and Dark focus states on Apple TV).
   - Respect `@Environment(\.accessibilityReduceTransparency)`, `@Environment(\.accessibilityReduceMotion)`, and `@Environment(\.colorSchemeContrast)`.
   - Ensure `DemoDataStore` stays in sync with any new API models or tabs so Demo Mode works end-to-end.
5. **Documentation**: Update `README.md`, `README.fr.md`, and relevant guides in `docs/en/` and `docs/fr/` when adding user-facing features or changing scripts.

## Related Repositories

- Backend / API contract changes belong in [Fairy-Jeux/pve-panel](https://github.com/Fairy-Jeux/pve-panel).
- Desktop (Windows/Linux) and Android client changes belong in [Fairy-Jeux/pve-center-clients](https://github.com/Fairy-Jeux/pve-center-clients).
- Documentation portal updates belong in [Fairy-Jeux/pve-center-website](https://github.com/Fairy-Jeux/pve-center-website).
