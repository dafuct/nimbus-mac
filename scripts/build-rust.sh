#!/usr/bin/env bash
# Build the Rust accelerator as a universal (arm64 + x86_64) static library and
# regenerate the UniFFI Swift bindings. Invoke from an Xcode "Run Script" build
# phase (before "Compile Sources") or by hand.
#
#   scripts/build-rust.sh [debug|release]
#
# Outputs:
#   rust/target/universal/libnimbus_core.a          (link this into the app)
#   Sources/NimbusFFI/generated/nimbus_core.swift   (Swift bindings)
#   Sources/NimbusFFI/generated/nimbus_coreFFI.h    (C header)
#   Sources/NimbusFFI/generated/nimbus_coreFFI.modulemap

set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$ROOT/rust"
GEN_DIR="$ROOT/Sources/NimbusFFI/generated"
UNIVERSAL_DIR="$RUST_DIR/target/universal"

CARGO_FLAGS=(--features ffi)
TARGET_SUBDIR="debug"
if [[ "$CONFIG" == "release" ]]; then
    CARGO_FLAGS+=(--release)
    TARGET_SUBDIR="release"
fi

echo "▶ Ensuring Rust targets are installed…"
rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null

echo "▶ Building nimbus_core ($CONFIG) for arm64 + x86_64…"
( cd "$RUST_DIR" && cargo build "${CARGO_FLAGS[@]}" --target aarch64-apple-darwin )
( cd "$RUST_DIR" && cargo build "${CARGO_FLAGS[@]}" --target x86_64-apple-darwin )

echo "▶ Creating universal static library…"
mkdir -p "$UNIVERSAL_DIR"
lipo -create \
    "$RUST_DIR/target/aarch64-apple-darwin/$TARGET_SUBDIR/libnimbus_core.a" \
    "$RUST_DIR/target/x86_64-apple-darwin/$TARGET_SUBDIR/libnimbus_core.a" \
    -output "$UNIVERSAL_DIR/libnimbus_core.a"
echo "  → $UNIVERSAL_DIR/libnimbus_core.a"

echo "▶ Generating Swift bindings…"
"$ROOT/scripts/gen-bindings.sh"

echo "✅ Done."
