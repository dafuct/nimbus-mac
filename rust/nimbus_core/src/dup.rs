//! Exact-duplicate detection via parallel BLAKE3 content hashing.
//!
//! This is the canonical "Rust earns its keep" path: Swift walks the file system
//! (I/O-bound) and groups candidates by byte length, then hands a single size
//! bucket to [`hash_files`], which hashes every file in parallel and collapses
//! byte-identical content into groups. Identical files necessarily share a size,
//! so per-bucket calls stay correct while letting Swift own progress and
//! cancellation one bucket at a time.

use rayon::prelude::*;
use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// A set of two or more files whose contents are byte-for-byte identical.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DuplicateGroup {
    /// Hex BLAKE3 digest shared by every file in the group.
    pub digest: String,
    /// Size in bytes of each (identical) file.
    pub file_size: u64,
    /// Absolute paths of the duplicate files, deterministically sorted.
    pub paths: Vec<String>,
}

impl DuplicateGroup {
    /// Bytes reclaimable if all but one copy is removed.
    pub fn reclaimable_bytes(&self) -> u64 {
        self.file_size
            .saturating_mul(self.paths.len().saturating_sub(1) as u64)
    }
}

/// A file that could not be read; surfaced rather than silently dropped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HashError {
    pub path: String,
    pub message: String,
}

/// Result of hashing one candidate bucket.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct HashOutcome {
    pub groups: Vec<DuplicateGroup>,
    pub errors: Vec<HashError>,
}

/// Hash every candidate path in parallel and bucket identical content together.
///
/// Unreadable files are reported in [`HashOutcome::errors`] and never abort the
/// run. Groups are returned largest-file-first for stable, useful ordering.
pub fn hash_files<I, S>(paths: I) -> HashOutcome
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let paths: Vec<String> = paths.into_iter().map(|s| s.as_ref().to_owned()).collect();

    let hashed: Vec<Result<(String, u64, String), HashError>> = paths
        .par_iter()
        .map(|p| match hash_one(p) {
            Ok((digest, size)) => Ok((digest, size, p.clone())),
            Err(message) => Err(HashError {
                path: p.clone(),
                message,
            }),
        })
        .collect();

    let mut buckets: HashMap<String, (u64, Vec<String>)> = HashMap::new();
    let mut errors = Vec::new();
    for item in hashed {
        match item {
            Ok((digest, size, path)) => {
                let entry = buckets.entry(digest).or_insert_with(|| (size, Vec::new()));
                entry.1.push(path);
            }
            Err(err) => errors.push(err),
        }
    }

    let mut groups: Vec<DuplicateGroup> = buckets
        .into_iter()
        .filter(|(_, (_, members))| members.len() > 1)
        .map(|(digest, (file_size, mut members))| {
            members.sort();
            DuplicateGroup {
                digest,
                file_size,
                paths: members,
            }
        })
        .collect();

    groups.sort_by(|a, b| {
        b.file_size
            .cmp(&a.file_size)
            .then_with(|| a.digest.cmp(&b.digest))
    });
    errors.sort_by(|a, b| a.path.cmp(&b.path));

    HashOutcome { groups, errors }
}

fn hash_one(path: &str) -> Result<(String, u64), String> {
    let p = Path::new(path);
    let meta = fs::metadata(p).map_err(|e| format!("metadata: {e}"))?;
    let size = meta.len();

    let mut hasher = blake3::Hasher::new();
    if size > 0 {
        // Memory-map keeps large files off the heap; empty files map poorly on
        // some filesystems, so we skip straight to the (well-defined) empty digest.
        hasher.update_mmap(p).map_err(|e| format!("read: {e}"))?;
    }
    Ok((hasher.finalize().to_hex().to_string(), size))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn write_file(dir: &Path, name: &str, contents: &[u8]) -> String {
        let path = dir.join(name);
        let mut f = fs::File::create(&path).unwrap();
        f.write_all(contents).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn groups_identical_content_and_ignores_unique() {
        let dir = tempfile::tempdir().unwrap();
        let a = write_file(dir.path(), "a.bin", b"hello world");
        let b = write_file(dir.path(), "b.bin", b"hello world");
        let c = write_file(dir.path(), "c.bin", b"hello world");
        let _unique = write_file(dir.path(), "u.bin", b"different bytes");

        let outcome = hash_files([a.clone(), b.clone(), c.clone(), _unique]);

        assert_eq!(outcome.errors, vec![]);
        assert_eq!(outcome.groups.len(), 1, "only the triplet is a duplicate");
        let group = &outcome.groups[0];
        assert_eq!(group.paths, {
            let mut v = vec![a, b, c];
            v.sort();
            v
        });
        assert_eq!(group.file_size, b"hello world".len() as u64);
        assert_eq!(group.reclaimable_bytes(), group.file_size * 2);
    }

    #[test]
    fn empty_files_are_all_duplicates_of_each_other() {
        let dir = tempfile::tempdir().unwrap();
        let a = write_file(dir.path(), "a", b"");
        let b = write_file(dir.path(), "b", b"");

        let outcome = hash_files([a, b]);
        assert_eq!(outcome.groups.len(), 1);
        assert_eq!(outcome.groups[0].file_size, 0);
    }

    #[test]
    fn unreadable_path_is_reported_not_fatal() {
        let dir = tempfile::tempdir().unwrap();
        let a = write_file(dir.path(), "a.bin", b"payload");
        let b = write_file(dir.path(), "b.bin", b"payload");
        let missing = dir.path().join("nope.bin").to_string_lossy().into_owned();

        let outcome = hash_files([a, b, missing.clone()]);
        assert_eq!(outcome.groups.len(), 1, "the readable pair still groups");
        assert_eq!(outcome.errors.len(), 1);
        assert_eq!(outcome.errors[0].path, missing);
    }

    #[test]
    fn no_duplicates_yields_no_groups() {
        let dir = tempfile::tempdir().unwrap();
        let a = write_file(dir.path(), "a", b"one");
        let b = write_file(dir.path(), "b", b"two");
        let outcome = hash_files([a, b]);
        assert!(outcome.groups.is_empty());
    }
}
