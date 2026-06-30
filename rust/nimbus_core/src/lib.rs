//! `nimbus_core` — the narrow CPU-bound accelerator behind Nimbus.
//!
//! Scope is deliberately tiny: parallel content hashing for exact duplicates
//! ([`dup`]) and perceptual hashing for similar photos ([`phash`]). Everything
//! else — file-system traversal, system APIs, orchestration, UI — lives in Swift.
//! This crate exists only because that hashing work is genuinely CPU-bound and
//! parallelizes cleanly with rayon, which is where Rust pays for the FFI seam.

pub mod dup;
pub mod phash;

// The UniFFI surface is compiled only for the staged library build, so the pure
// algorithms above can be unit-tested with no binding machinery present.
#[cfg(feature = "ffi")]
mod ffi;

#[cfg(feature = "ffi")]
uniffi::setup_scaffolding!();
