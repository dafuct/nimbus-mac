#!/usr/bin/env bash
# Regenerate the UniFFI Swift bindings from a freshly built dylib (library mode).
# Called by build-rust.sh; can also be run standalone.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$ROOT/rust"
GEN_DIR="$ROOT/Sources/NimbusFFI/generated"

echo "▶ Building host dylib for bindgen…"
( cd "$RUST_DIR" && cargo build --release --features ffi )

DYLIB="$RUST_DIR/target/release/libnimbus_core.dylib"
mkdir -p "$GEN_DIR"

echo "▶ Running uniffi-bindgen (library mode)…"
( cd "$RUST_DIR" && cargo run -q --features cli --bin uniffi-bindgen -- \
    generate --library "$DYLIB" --language swift --out-dir "$GEN_DIR" )

# UniFFI emits "<name>FFI.modulemap"; ensure it's named so Xcode's module map
# setting can find it. (Already correct for nimbus_core.)
echo "  → $GEN_DIR"
ls -1 "$GEN_DIR"
