# Nimbus

A native macOS maintenance & cleanup utility (CleanMyMac-class) for macOS 14+ on
Apple Silicon and Intel. **Swift + SwiftUI is the core**; **Rust is a narrow
accelerator** used only for genuinely CPU-bound work (parallel content hashing for
duplicates, perceptual hashing for similar photos) over a UniFFI bridge.

> Architecture philosophy: the file system walk is I/O-bound and stays in Swift
> (`FileManager`). Rust earns the FFI seam only where parallel CPU work pays for
> it — `rayon` + `blake3` + perceptual hashing — and nowhere else.

## Status — what's built and verified

| Layer | State | Verified |
|---|---|---|
| Rust core (`nimbus_core`): dup hashing, perceptual hashing, BK-tree clustering | ✅ complete | `cargo test` — 10/10 |
| FFI boundary (UniFFI) + generated Swift bindings | ✅ complete | dylib built, bindings generated end-to-end |
| NimbusKit domain layer (scanning, treemap, selection, 6 modules, safety engine) | ✅ complete | `swift test` — 30/30 |
| View models (MVVM, headless-testable) | ✅ complete | `swift test` — 2/2 |
| SwiftUI app + privileged helper + entitlements | ✅ complete | **builds via XcodeGen + xcodebuild (BUILD SUCCEEDED)** |
| Visual fidelity to `Nimbus.dc.html` | ✅ applied (core screens) | dark theme, purple accent, sidebar, Smart Scan, Health |

Total automated tests green: **42** (10 Rust + 32 Swift). The full app (SwiftUI +
Rust bridge + helper) compiles and links into a signed `Nimbus.app`.

## Build & run the app

```bash
brew install xcodegen        # one-time
xcodegen generate            # writes Nimbus.xcodeproj from project.yml
xcodebuild -project Nimbus.xcodeproj -scheme Nimbus -configuration Debug build
# or: open Nimbus.xcodeproj   and ⌘R in Xcode
```

The Xcode build runs `scripts/build-rust.sh` (universal `libnimbus_core.a` +
regenerated UniFFI bindings) as a pre-build phase, links it, and embeds the
privileged helper. Remaining visual polish (Duplicates tabs, Cleanup expandable
rows, Lens detail panel, Settings/Uninstaller/Performance/Onboarding) is the next
iteration — every screen's domain logic already exists and is tested.

## Repository layout

```
nimbus/
├── Package.swift              # SPM: NimbusKit + NimbusViewModels (+ tests) — Rust-free, builds headless
├── rust/                      # Cargo workspace
│   └── nimbus_core/           # the accelerator crate
│       ├── src/dup.rs         # BLAKE3 + rayon exact-duplicate grouping
│       ├── src/phash.rs       # dHash + BK-tree similarity clustering
│       ├── src/ffi.rs         # UniFFI surface (feature "ffi")
│       └── src/lib.rs
├── Sources/
│   ├── NimbusKit/             # domain/service core (pure Swift, fully tested)
│   │   ├── Scanning/          # the SINGLE shared FS traversal + selection store
│   │   ├── SpaceLens/         # tree builder + squarified treemap (pure)
│   │   ├── Duplicates/        # scanners + hashing protocols (Rust seam)
│   │   ├── Safety/            # safety-rules engine, catalog, guard, Remover
│   │   ├── Cleanup/ Uninstaller/ Performance/ Health/ Privileged/ Support/
│   ├── NimbusViewModels/      # @Observable MVVM view models (no SwiftUI dep)
│   └── NimbusFFI/             # generated UniFFI bindings + Rust↔Swift adapters (Xcode target)
├── App/Nimbus/                # SwiftUI app target (default skin)
├── Helper/NimbusHelper/       # privileged SMAppService daemon
├── Shared/HelperProtocol.swift# XPC contract (app + helper)
├── Config/                    # entitlements, Info.plist, launchd plist
├── scripts/                   # build-rust.sh, gen-bindings.sh
└── docs/                      # ARCHITECTURE, FFI, SAFETY, DISTRIBUTION
```

## Build & test

```bash
# Pure Swift core + view models (no Rust needed):
swift test

# Rust accelerator:
cd rust && cargo test

# Universal static lib + regenerated Swift bindings (for the app):
./scripts/build-rust.sh release
```

The SwiftUI app + helper are assembled in an Xcode project that links
`rust/target/universal/libnimbus_core.a` and the `nimbus_coreFFI` module map. See
[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) for the Xcode wiring, entitlements,
helper lifecycle, hardened runtime, and notarization.

## Docs

- [Architecture](docs/ARCHITECTURE.md) — layers, DRY scanning core, concurrency.
- [FFI boundary](docs/FFI.md) — the Rust API surface, generated Swift, end-to-end duplicate flow.
- [Safety model](docs/SAFETY.md) — rules engine, dispositions, example catalog, Trash-by-default.
- [Distribution](docs/DISTRIBUTION.md) — Xcode integration, entitlements, helper, sandbox trade-off, notarization.

## Note on the design

This implementation targets the `Nimbus.dc.html` Claude Design source. The design
file could not be retrieved in this environment (the design tool needs an
interactive `/design-login`), so the SwiftUI views use a neutral **default skin**
centralized in `App/Nimbus/Support/DesignTokens.swift`. Provide `Nimbus.dc.html`
(or seed it via Claude Design's "Send to Claude Code Web") to re-skin precisely —
only `Theme` and the view bodies change; the entire architecture stays put.
