## Summary

Describe what this pull request changes and why.

## Platforms Tested

- [ ] SwiftPM (`swift build`)
- [ ] macOS (`PVECenter` scheme / `MenuBarExtra`)
- [ ] iPhone / iPad Simulator (`PVECenter-iOS` scheme, Light & Dark mode)
- [ ] Apple TV Simulator (`PVECenter` scheme on `tvOS`)
- [ ] Physical device deployment (`./scripts/deploy-device.sh`)

## Checklist

- [ ] Code compiles cleanly with Swift 6 strict concurrency (zero new warnings)
- [ ] `bash -n scripts/*.sh` and `plutil -lint PVECenter/Resources/Info.plist` pass
- [ ] No real tokens, `.p8` keys, `.mobileprovision` files, or private homelab URLs included
- [ ] Demo Mode (`DemoDataStore`) and accessibility (`reduceTransparency`, `reduceMotion`, VoiceOver/tvOS Focus) verified where UI changed
- [ ] Bilingual documentation (`README.md` / `README.fr.md` / `docs/`) updated if user-facing behavior changed
