//! In-tree UniFFI binding generator (library mode).
//!
//! Run via `cargo run --features cli --bin uniffi-bindgen -- generate \
//!   --library <path-to-dylib> --language swift --out-dir <dir>`.
//! `scripts/gen-bindings.sh` wraps this.
fn main() {
    uniffi::uniffi_bindgen_main()
}
