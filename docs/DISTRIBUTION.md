# Distribution, permissions & build

## Xcode project assembly

`Package.swift` builds the Rust-free, headless-testable core. The shippable app is
an Xcode project (`Nimbus.xcodeproj`) with three targets:

1. **Nimbus** (app) — depends on the `NimbusKit` + `NimbusViewModels` SPM package;
   includes `App/Nimbus/**`, `Sources/NimbusFFI/**` (generated bindings +
   `RustHashers.swift`), and `Shared/HelperProtocol.swift`.
2. **NimbusHelper** (command-line tool) — `Helper/NimbusHelper/main.swift` +
   `Shared/HelperProtocol.swift` (shared membership).
3. (SPM package referenced locally.)

App target build settings:

- Add a **Run Script** phase (before *Compile Sources*): `"$SRCROOT/scripts/build-rust.sh" release`
- **Other Linker Flags**: link `rust/target/universal/libnimbus_core.a`
- **Import Paths / Module Map**: `Sources/NimbusFFI/generated/nimbus_coreFFI.modulemap`
- **ENABLE_HARDENED_RUNTIME = YES**, **Code Signing Entitlements = Config/Nimbus.entitlements**
- Copy `Config/com.nimbus.app.helper.plist` → `Contents/Library/LaunchDaemons/`
- Copy the built `NimbusHelper` → `Contents/MacOS/NimbusHelper`

## Permissions

### Full Disk Access (TCC, runtime)
FDA is **not** an entitlement — it's a TCC permission the user grants in
**System Settings → Privacy & Security → Full Disk Access**. Without it, scans of
protected locations (`~/Library/Mail`, `~/Library/Safari`, other apps' containers)
silently return fewer results; `FileSystemScanner` already skips unreadable
subdirectories rather than failing. The app should detect this and present an
onboarding step that deep-links to the FDA pane and explains why.

### Privileged helper (SMAppService)
Operations that need root — flushing the DNS cache, reindexing Spotlight on `/`,
removing system-owned caches/logs — run in `NimbusHelper`, a daemon managed by
`SMAppService.daemon(plistName:)`.

Lifecycle:

```
App launch ─▶ XPCHelperClient.isInstalled()  (service.status == .enabled?)
   │ no
   ▼
User clicks "Enable maintenance features"
   ▼
XPCHelperClient.install() → SMAppService.daemon(...).register()
   ▼
macOS prompts approval in System Settings → Login Items & Extensions
   ▼
Approved → daemon runs as root, listening on mach service "com.nimbus.app.helper"
   ▼
App ↔ helper via NSXPCConnection(machServiceName:options:.privileged)
        (helper verifies client team id before accepting — see listener delegate)
   ▼
Uninstall: SMAppService...unregister()
```

IPC contract: `Shared/HelperProtocol.swift` (`@objc` + reply blocks, wrapped in
async/await by `XPCHelperClient`). The helper **re-validates every path against
its own guard** — it never trusts the client.

## Sandbox trade-off

Nimbus ships **non-sandboxed**. The App Sandbox cannot:

- read other apps' caches/logs/containers (no system-junk cleanup),
- run maintenance tools (`mdutil`, `dscacheutil`),
- install a privileged helper that touches system locations.

A sandboxed Mac App Store build would degrade to: Space Lens / Duplicates /
Similar Photos limited to user-selected folders (security-scoped bookmarks), no
system Cleanup, no Performance tasks, no helper. So Nimbus targets a **Developer
ID, non-sandboxed, hardened-runtime, notarized** build distributed via **DMG**.

## Hardened Runtime + notarization

```bash
# 1. Build universal Rust lib + bindings
./scripts/build-rust.sh release

# 2. Archive in Xcode (Developer ID), or xcodebuild archive ...

# 3. Sign app + helper with Hardened Runtime (Xcode does this with the
#    entitlements + ENABLE_HARDENED_RUNTIME set). Verify:
codesign --verify --deep --strict --verbose=2 Nimbus.app
spctl --assess --type execute --verbose Nimbus.app

# 4. Notarize
xcrun notarytool submit Nimbus.dmg --apple-id "$APPLE_ID" \
     --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PW" --wait

# 5. Staple
xcrun stapler staple Nimbus.dmg
```

Both the app and the embedded helper must be signed with the same Developer ID and
Hardened Runtime; the helper's `AssociatedBundleIdentifiers` ties it to the app.

## Building without a paid Developer account

You can build, run, and share a DMG locally with **ad-hoc signing** — no Apple
Developer ID required:

```bash
scripts/package-dmg.sh      # Release build + ad-hoc sign + build/Nimbus.dmg
```

What works ad-hoc:
- The whole app runs on **your** machine (Space Lens, Duplicates, Cleanup,
  Uninstaller list, Health, Settings — everything that doesn't need root).

What needs a Developer ID (the app degrades gracefully until then):
- **Privileged helper (SMAppService)** — `register()` is rejected for ad-hoc
  builds, so DNS flush / Spotlight reindex / system-owned cache removal stay
  disabled. The Performance screen shows an "Увімкнути" banner and a clear
  message instead of failing silently (see `PerformanceViewModel.installHelper`).
- **Notarization** — `scripts/notarize.sh` is ready to run once you have a
  "Developer ID Application" certificate; until then other Macs show a Gatekeeper
  warning (right-click → Open to bypass locally).

When you get a Developer ID: set `CODE_SIGN_IDENTITY`/`DEVELOPMENT_TEAM` in
`project.yml`, re-`xcodegen generate`, `scripts/package-dmg.sh`, then
`scripts/notarize.sh`.

## Auto-updates (Sparkle) — optional

For out-of-App-Store updates, integrate [Sparkle](https://sparkle-project.org):

1. Add the Sparkle SPM package to the app target in `project.yml`
   (`https://github.com/sparkle-project/Sparkle`).
2. Generate an EdDSA key pair (`generate_keys`) and add the public key as
   `SUPublicEDKey` in Info.plist; set `SUFeedURL` to your hosted `appcast.xml`.
3. On each release, sign the DMG with `sign_update` and publish the appcast entry.

Sparkle also expects Developer ID + notarization for the delta/full updates to
pass Gatekeeper on end-user machines, so it pairs with the steps above.

