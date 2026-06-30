# FFI boundary

## Bridge choice: UniFFI

We use **UniFFI** (over swift-bridge). Reason: the return shapes are nested
records with `Vec<String>` fields and a fallible decode path. UniFFI maps those to
idiomatic Swift structs, arrays, optionals, and `throws` with zero hand-written
glue — exactly the "collect paths → return groups" shape this accelerator needs.
swift-bridge shines for tight value/opaque-handle interop but is fiddlier for
nested collection returns.

The crate exposes the surface only under `--features ffi`, so the pure algorithms
in `dup.rs` / `phash.rs` unit-test (`cargo test`) with no binding machinery.

## Rust API surface (`rust/nimbus_core/src/ffi.rs`)

```rust
#[uniffi::export] fn hash_files(paths: Vec<String>) -> HashOutcome;
#[uniffi::export] fn dhash_files(paths: Vec<String>) -> PhashOutcome;
#[uniffi::export] fn dhash_luma8(width: u32, height: u32, luma: Vec<u8>) -> Option<u64>;
#[uniffi::export] fn group_similar(items: Vec<PhashItem>, max_distance: u32) -> Vec<SimilarGroup>;

#[derive(uniffi::Record)] struct DuplicateGroup { digest: String, file_size: u64, paths: Vec<String> }
#[derive(uniffi::Record)] struct HashOutcome    { groups: Vec<DuplicateGroup>, errors: Vec<HashError> }
#[derive(uniffi::Record)] struct PhashItem      { path: String, hash: u64 }
#[derive(uniffi::Record)] struct PhashOutcome   { items: Vec<PhashItem>, errors: Vec<PhashError> }
#[derive(uniffi::Record)] struct SimilarGroup   { paths: Vec<String> }
// + HashError { path, message }, PhashError { path, message }
```

## Generated Swift bindings (verified)

Running `scripts/gen-bindings.sh` produced (in `Sources/NimbusFFI/generated/`):

```swift
public func hashFiles(paths: [String]) -> HashOutcome
public func dhashFiles(paths: [String]) -> PhashOutcome
public func dhashLuma8(width: UInt32, height: UInt32, luma: Data) -> UInt64?
public func groupSimilar(items: [PhashItem], maxDistance: UInt32) -> [SimilarGroup]

public struct DuplicateGroup { public var digest: String; public var fileSize: UInt64; public var paths: [String] }
public struct HashOutcome    { public var groups: [DuplicateGroup]; public var errors: [HashError] }
public struct PhashItem      { public var path: String; public var hash: UInt64 }
public struct PhashOutcome   { public var items: [PhashItem]; public var errors: [PhashError] }
public struct SimilarGroup   { public var paths: [String] }
```

Plus the low-level `nimbus_coreFFI.h` + `nimbus_coreFFI.modulemap` (the C ABI
UniFFI builds on — `RustBuffer`-based).

## End-to-end duplicate-detection data flow

```
SwiftUI ──▶ DuplicatesViewModel.scan()
                │  (Sources/NimbusViewModels)
                ▼
        DuplicateScanner.findDuplicates(roots:)         (NimbusKit, I/O-bound)
                │  1. FileSystemScanner streams FileEntry (Swift FileManager)
                │  2. bucket candidates by exact byte size; drop singletons
                ▼
        ContentHashing.hashBucket([String])             (protocol seam)
                │
                ▼
        RustContentHasher  ──Task.detached──▶  hashFiles(paths:)   (Sources/NimbusFFI)
                                                   │  UniFFI → C ABI
                                                   ▼
                                          nimbus_core::dup::hash_files
                                                   │  rayon: parallel BLAKE3 per file
                                                   │  bucket by digest, keep ≥2
                                                   ▼
                                          HashOutcome { groups, errors }
                │  ◀───────────────────────────────┘  (lifted to Swift structs)
                ▼
        map → [DuplicateGroup] (domain) ──▶ ViewModel.phase = .loaded
                                          ──▶ SelectionStore pre-selects all-but-one
                                          ──▶ Remover (Trash by default)
```

Key property: **Swift drives the loop** (one Rust call per size-bucket), so
progress reporting and cancellation are pure structured-concurrency in Swift while
Rust stays stateless and embarrassingly parallel. Similar-photos is the same
shape, except clustering is global: Swift batches `dhash_files`, accumulates all
hashes, then makes a single `group_similar` call. HEIC/RAW that the `image` crate
can't decode are decoded on the Swift side via ImageIO and fed through
`dhash_luma8` (see `RustPerceptualHasher.lumaHash`).

## Build integration

`scripts/build-rust.sh` builds `libnimbus_core.a` universal (arm64 + x86_64 via
`lipo`) and regenerates the bindings. In Xcode:

1. Add a "Run Script" phase calling `scripts/build-rust.sh release` before Compile.
2. Add `Sources/NimbusFFI/generated/*.swift` + `RustHashers.swift` to the app target.
3. Set **Import Paths** / **Module Map File** to `nimbus_coreFFI.modulemap`.
4. Link `rust/target/universal/libnimbus_core.a` (+ `libresolv`, `Security` as needed).
