//! UniFFI binding surface — the *only* thing Swift sees.
//!
//! Deliberately thin: every record below is a flat projection of a pure type in
//! `dup`/`phash`, and every exported function is a one-line delegate. Keeping the
//! algorithms FFI-free means `cargo test` exercises them with no UniFFI toolchain,
//! while this module (compiled only under `--features ffi`) defines the contract.
//!
//! ## Why UniFFI over swift-bridge
//! The return shapes here are nested records with `Vec<String>` fields and a
//! fallible decode path. UniFFI maps those to idiomatic Swift structs, arrays,
//! optionals, and `throws` with zero hand-written glue, which is exactly the
//! "collect paths → return groups" shape this accelerator needs. swift-bridge
//! shines for tight value/opaque-handle interop but is fiddlier for nested
//! collection returns. See `docs/FFI.md` for the generated Swift surface.

use crate::{dup, phash};

#[derive(uniffi::Record)]
pub struct DuplicateGroup {
    pub digest: String,
    pub file_size: u64,
    pub paths: Vec<String>,
}

#[derive(uniffi::Record)]
pub struct HashError {
    pub path: String,
    pub message: String,
}

#[derive(uniffi::Record)]
pub struct HashOutcome {
    pub groups: Vec<DuplicateGroup>,
    pub errors: Vec<HashError>,
}

#[derive(uniffi::Record)]
pub struct PhashItem {
    pub path: String,
    pub hash: u64,
}

#[derive(uniffi::Record)]
pub struct PhashError {
    pub path: String,
    pub message: String,
}

#[derive(uniffi::Record)]
pub struct PhashOutcome {
    pub items: Vec<PhashItem>,
    pub errors: Vec<PhashError>,
}

#[derive(uniffi::Record)]
pub struct SimilarGroup {
    pub paths: Vec<String>,
}

impl From<dup::DuplicateGroup> for DuplicateGroup {
    fn from(g: dup::DuplicateGroup) -> Self {
        DuplicateGroup {
            digest: g.digest,
            file_size: g.file_size,
            paths: g.paths,
        }
    }
}

impl From<dup::HashError> for HashError {
    fn from(e: dup::HashError) -> Self {
        HashError {
            path: e.path,
            message: e.message,
        }
    }
}

impl From<dup::HashOutcome> for HashOutcome {
    fn from(o: dup::HashOutcome) -> Self {
        HashOutcome {
            groups: o.groups.into_iter().map(Into::into).collect(),
            errors: o.errors.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<phash::PhashItem> for PhashItem {
    fn from(i: phash::PhashItem) -> Self {
        PhashItem {
            path: i.path,
            hash: i.hash,
        }
    }
}

impl From<phash::PhashError> for PhashError {
    fn from(e: phash::PhashError) -> Self {
        PhashError {
            path: e.path,
            message: e.message,
        }
    }
}

impl From<phash::PhashOutcome> for PhashOutcome {
    fn from(o: phash::PhashOutcome) -> Self {
        PhashOutcome {
            items: o.items.into_iter().map(Into::into).collect(),
            errors: o.errors.into_iter().map(Into::into).collect(),
        }
    }
}

/// Hash one size bucket of candidate paths and return byte-identical groups.
/// Swift calls this once per size bucket so it can drive progress + cancellation.
#[uniffi::export]
pub fn hash_files(paths: Vec<String>) -> HashOutcome {
    dup::hash_files(paths).into()
}

/// Perceptually hash a batch of image paths the `image` crate can decode.
#[uniffi::export]
pub fn dhash_files(paths: Vec<String>) -> PhashOutcome {
    phash::dhash_files(paths).into()
}

/// Perceptually hash a raw 8-bit luma buffer (Swift-decoded HEIC/RAW path).
/// Returns `None` if the buffer length doesn't match `width * height`.
#[uniffi::export]
pub fn dhash_luma8(width: u32, height: u32, luma: Vec<u8>) -> Option<u64> {
    phash::dhash_luma8(width, height, &luma)
}

/// Cluster perceptually-similar items. Swift accumulates all hashes (from
/// `dhash_files` and/or `dhash_luma8`) then calls this once.
#[uniffi::export]
pub fn group_similar(items: Vec<PhashItem>, max_distance: u32) -> Vec<SimilarGroup> {
    let internal: Vec<phash::PhashItem> = items
        .into_iter()
        .map(|i| phash::PhashItem {
            path: i.path,
            hash: i.hash,
        })
        .collect();
    phash::group_similar(&internal, max_distance)
        .into_iter()
        .map(|paths| SimilarGroup { paths })
        .collect()
}
