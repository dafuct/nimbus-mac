# Nimbus

[![CI](https://github.com/dafuct/nimbus-mac/actions/workflows/ci.yml/badge.svg)](https://github.com/dafuct/nimbus-mac/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

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
| NimbusKit domain layer (scanning, treemap, selection, 6 modules, safety engine) | ✅ complete | `swift test` — green |
| View models (MVVM, headless-testable) | ✅ complete | `swift test` — green |
| SwiftUI app + privileged helper + entitlements | ✅ complete | **builds via XcodeGen + xcodebuild (BUILD SUCCEEDED)** |
| Visual fidelity to `Nimbus.dc.html` | ✅ applied (core screens) | dark theme, purple accent, sidebar, Smart Scan, Health |

Total automated tests green: **50** (10 Rust + 40 Swift), all run in CI on every
push and pull request. The full app (SwiftUI + Rust bridge + helper) compiles and
links into a signed `Nimbus.app`.

## Build & run the app

```bash
git clone https://github.com/dafuct/nimbus-mac.git && cd nimbus-mac
brew install xcodegen        # one-time
xcodegen generate            # writes Nimbus.xcodeproj from project.yml
xcodebuild -project Nimbus.xcodeproj -scheme Nimbus -configuration Debug build
# or: open Nimbus.xcodeproj   and ⌘R in Xcode
```

To package a distributable disk image (universal, ad-hoc signed) run
`scripts/package-dmg.sh`; for a Developer-ID + notarized build run
`scripts/notarize.sh` afterward.

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
`docs/DISTRIBUTION.md` (kept local) for the Xcode wiring, entitlements, helper
lifecycle, hardened runtime, and notarization.

## Docs

Extended design docs live under `docs/` locally but are intentionally **not
tracked** in git (see `.gitignore`). They cover:

- **Architecture** — layers, DRY scanning core, concurrency.
- **FFI boundary** — the Rust API surface, generated Swift, end-to-end duplicate flow.
- **Safety model** — rules engine, dispositions, example catalog, Trash-by-default.
- **Distribution** — Xcode integration, entitlements, helper, sandbox trade-off, notarization.

## Note on the design

This implementation targets the `Nimbus.dc.html` Claude Design source. The design
file could not be retrieved in this environment (the design tool needs an
interactive `/design-login`), so the SwiftUI views use a neutral **default skin**
centralized in `App/Nimbus/Support/DesignTokens.swift`. Provide `Nimbus.dc.html`
(or seed it via Claude Design's "Send to Claude Code Web") to re-skin precisely —
only `Theme` and the view bodies change; the entire architecture stays put.

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push to `main`
and on every pull request (`macos-15` runner):

- **`cargo test`** — the pure Rust algorithms (dup grouping, perceptual hashing, BK-tree).
- **`cargo build --release --features ffi`** — the UniFFI surface compiles.
- **`swift test`** — the NimbusKit domain layer + view models (headless, Rust-free).
- **`xcodegen generate` + `xcodebuild`** — the full SwiftUI app links (Debug, code signing off).

## License

Released under the [MIT License](LICENSE) © 2026 Dmytro Makarenko.
