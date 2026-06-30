# Architecture

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│ Presentation  — SwiftUI views (App/Nimbus) + MVVM view models  │
│                 (Sources/NimbusViewModels, @Observable)        │
├──────────────────────────────────────────────────────────────┤
│ Domain/Service (Swift, Sources/NimbusKit)                      │
│   • Scanning: ONE FileSystemScanner + SelectionStore (shared)  │
│   • SpaceLens, Duplicates, SimilarPhotos, Cleanup, Uninstaller │
│   • Safety: rules engine, catalog, CriticalPathGuard, Remover  │
│   • Health (mach), Performance, Privileged helper client       │
├──────────────────────────────────────────────────────────────┤
│ Performance accelerator (Rust, rust/nimbus_core)              │
│   • dup.rs  : BLAKE3 + rayon  → exact-duplicate groups         │
│   • phash.rs: dHash + BK-tree → similarity clusters            │
│   • ffi.rs  : UniFFI surface (the only thing Swift sees)       │
└──────────────────────────────────────────────────────────────┘
```

The dependency arrow points down only. `NimbusKit` knows nothing about SwiftUI,
and it knows nothing about Rust — it talks to the accelerator through the
`ContentHashing` / `PerceptualHashing` protocols, which the Xcode app satisfies
with the Rust-backed adapters in `Sources/NimbusFFI`. That's what lets the whole
domain layer build and unit-test headlessly with `swift test`.

## The DRY core: one traversal, one selection model

The single most important anti-duplication decision: **every module consumes the
same `FileSystemScanner`**. It is the only directory walk in the codebase.

- `FileSystemScanner.entries(root:options:)` yields a stream of `FileEntry`
  (files only), I/O-bound, cancellation-aware, resilient to unreadable subdirs.
- **Space Lens** folds that stream into an aggregated tree (`DiskUsageTreeBuilder`)
  and renders it with the pure `TreemapLayout` (squarified).
- **Duplicates** buckets the stream by size, sends real candidates to Rust.
- **Similar Photos** filters the stream by image extension, batches to Rust.
- **Cleanup / Uninstaller** size items by folding the stream over a subtree.

Selection is likewise shared: `SelectionStore<Item: Selectable>` provides
toggle / select-all / "keep one, remove the rest" / reclaimable-bytes math once,
for Duplicates, Cleanup, and Uninstaller alike.

Path canonicalization (the `/private/var` firmlink) lives once in
`PathCanonical` and is used by the exclusion matcher, the safety rules, and the
critical-path guard — no per-component copies.

## Concurrency model

- Structured concurrency throughout: scans are `async` and honor the calling
  `Task`'s cancellation between entries (`try Task.checkCancellation()`), so long
  scans stop promptly when the user hits Cancel or navigates away.
- View models are `@MainActor @Observable`; they launch scans in a child `Task`,
  marshal progress back to the main actor, and expose a single `phase` enum the
  SwiftUI view projects.
- CPU-bound Rust calls are dispatched off the main actor (`Task.detached`) by the
  `RustHashers` adapters.
- Swift owns progress + cancellation by calling Rust per size-bucket / per batch
  (see [FFI.md](FFI.md)); Rust stays stateless.

## Error handling

Domain code throws typed `NimbusError` (or returns `Result`-like outcomes such as
`RemovalReport` / `ContentHashOutcome` that carry per-item failures). Nothing in
the service layer imports UI or servlet types. The presentation layer maps errors
to copy; cancellation is modeled as `NimbusError.cancelled` and treated as a
non-error reset.

## Why Rust only here

Profiling guidance baked into the design: the disk walk is I/O-bound — Rust would
not speed it up and would add an FFI boundary for nothing. The win is the
*parallel CPU* work: hashing thousands of candidate files (`blake3` + `rayon`) and
perceptually hashing/clustering a photo library. Those two modules are the entire
justification for the Rust crate; everything else is Swift.
