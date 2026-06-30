//! Perceptual hashing (difference hash) + similarity clustering for the
//! "Similar Photos" feature.
//!
//! Flow mirrors `dup`: Swift collects candidate image paths, Rust decodes and
//! hashes them in parallel ([`dhash_files`]), then a single cheap integer pass
//! ([`group_similar`]) clusters perceptually-close images. HEIC/RAW that the
//! `image` crate can't decode are decoded on the Swift side via ImageIO and fed
//! in through [`dhash_luma8`].

use rayon::prelude::*;
use std::collections::HashMap;

/// A 64-bit difference hash.
pub type Hash = u64;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PhashItem {
    pub path: String,
    pub hash: Hash,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PhashError {
    pub path: String,
    pub message: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PhashOutcome {
    pub items: Vec<PhashItem>,
    pub errors: Vec<PhashError>,
}

/// Compute a 9×8 difference hash from an 8-bit luminance buffer of arbitrary
/// size. Returns `None` if the buffer length doesn't match `width * height`.
///
/// This is the entry point Swift uses for formats Rust can't decode: ImageIO
/// produces a luma8 buffer, we resize + hash here.
pub fn dhash_luma8(width: u32, height: u32, luma: &[u8]) -> Option<Hash> {
    if width == 0 || height == 0 {
        return None;
    }
    if (width as usize).checked_mul(height as usize) != Some(luma.len()) {
        return None;
    }
    let img = image::GrayImage::from_raw(width, height, luma.to_vec())?;
    Some(dhash_image(&img))
}

fn dhash_image(img: &image::GrayImage) -> Hash {
    use image::imageops::{resize, FilterType};
    // 9 wide so each row yields 8 left>right comparisons -> 64 bits total.
    let small = resize(img, 9, 8, FilterType::Triangle);
    let mut hash: Hash = 0;
    let mut bit = 0u32;
    for y in 0..8u32 {
        for x in 0..8u32 {
            let left = small.get_pixel(x, y)[0];
            let right = small.get_pixel(x + 1, y)[0];
            if left > right {
                hash |= 1 << bit;
            }
            bit += 1;
        }
    }
    hash
}

/// Decode an image file and hash it. Used for formats the `image` crate handles.
pub fn dhash_file(path: &str) -> Result<Hash, String> {
    let img = image::open(path).map_err(|e| e.to_string())?.to_luma8();
    Ok(dhash_image(&img))
}

/// Hash a batch of image paths in parallel; failures are collected, not fatal.
pub fn dhash_files<I, S>(paths: I) -> PhashOutcome
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let paths: Vec<String> = paths.into_iter().map(|s| s.as_ref().to_owned()).collect();
    let results: Vec<Result<PhashItem, PhashError>> = paths
        .par_iter()
        .map(|p| {
            dhash_file(p)
                .map(|hash| PhashItem {
                    path: p.clone(),
                    hash,
                })
                .map_err(|message| PhashError {
                    path: p.clone(),
                    message,
                })
        })
        .collect();

    let mut out = PhashOutcome::default();
    for r in results {
        match r {
            Ok(item) => out.items.push(item),
            Err(err) => out.errors.push(err),
        }
    }
    out
}

/// Hamming distance between two hashes — number of differing bits.
#[inline]
pub fn hamming(a: Hash, b: Hash) -> u32 {
    (a ^ b).count_ones()
}

/// Cluster items whose hashes are within `max_distance` of each other.
///
/// A BK-tree answers "all hashes within distance d" queries in roughly
/// `O(log n)` instead of the naive `O(n)`, and union-find merges
/// transitively-similar items (A~B, B~C ⇒ {A,B,C}). Only clusters of two or
/// more are returned, each path list sorted, the list of clusters ordered by
/// descending size.
pub fn group_similar(items: &[PhashItem], max_distance: u32) -> Vec<Vec<String>> {
    if items.is_empty() {
        return Vec::new();
    }

    let mut uf = UnionFind::new(items.len());
    let mut tree: Option<BkNode> = None;
    for (idx, item) in items.iter().enumerate() {
        if let Some(root) = tree.as_mut() {
            let mut neighbors = Vec::new();
            root.query(item.hash, max_distance, &mut neighbors);
            for n in neighbors {
                uf.union(idx, n);
            }
            root.insert(item.hash, idx);
        } else {
            tree = Some(BkNode::new(item.hash, idx));
        }
    }

    let mut clusters: HashMap<usize, Vec<String>> = HashMap::new();
    for (idx, item) in items.iter().enumerate() {
        clusters
            .entry(uf.find(idx))
            .or_default()
            .push(item.path.clone());
    }

    let mut groups: Vec<Vec<String>> = clusters
        .into_values()
        .filter(|paths| paths.len() > 1)
        .map(|mut paths| {
            paths.sort();
            paths
        })
        .collect();
    groups.sort_by(|a, b| b.len().cmp(&a.len()).then_with(|| a[0].cmp(&b[0])));
    groups
}

// ---- BK-tree -------------------------------------------------------------

struct BkNode {
    hash: Hash,
    /// Item indices sharing exactly this hash (handles identical images).
    idxs: Vec<usize>,
    children: HashMap<u32, BkNode>,
}

impl BkNode {
    fn new(hash: Hash, idx: usize) -> Self {
        BkNode {
            hash,
            idxs: vec![idx],
            children: HashMap::new(),
        }
    }

    fn insert(&mut self, hash: Hash, idx: usize) {
        let d = hamming(self.hash, hash);
        if d == 0 {
            self.idxs.push(idx);
            return;
        }
        match self.children.get_mut(&d) {
            Some(child) => child.insert(hash, idx),
            None => {
                self.children.insert(d, BkNode::new(hash, idx));
            }
        }
    }

    fn query(&self, hash: Hash, max: u32, out: &mut Vec<usize>) {
        let d = hamming(self.hash, hash);
        if d <= max {
            out.extend(self.idxs.iter().copied());
        }
        let lo = d.saturating_sub(max);
        let hi = d.saturating_add(max);
        for (&dist, child) in &self.children {
            if dist >= lo && dist <= hi {
                child.query(hash, max, out);
            }
        }
    }
}

// ---- Union-Find ----------------------------------------------------------

struct UnionFind {
    parent: Vec<usize>,
    rank: Vec<u8>,
}

impl UnionFind {
    fn new(n: usize) -> Self {
        UnionFind {
            parent: (0..n).collect(),
            rank: vec![0; n],
        }
    }

    fn find(&mut self, x: usize) -> usize {
        let mut root = x;
        while self.parent[root] != root {
            root = self.parent[root];
        }
        // Path compression.
        let mut cur = x;
        while self.parent[cur] != root {
            let next = self.parent[cur];
            self.parent[cur] = root;
            cur = next;
        }
        root
    }

    fn union(&mut self, a: usize, b: usize) {
        let (ra, rb) = (self.find(a), self.find(b));
        if ra == rb {
            return;
        }
        match self.rank[ra].cmp(&self.rank[rb]) {
            std::cmp::Ordering::Less => self.parent[ra] = rb,
            std::cmp::Ordering::Greater => self.parent[rb] = ra,
            std::cmp::Ordering::Equal => {
                self.parent[rb] = ra;
                self.rank[ra] += 1;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(path: &str, hash: Hash) -> PhashItem {
        PhashItem {
            path: path.to_string(),
            hash,
        }
    }

    #[test]
    fn hamming_counts_differing_bits() {
        assert_eq!(hamming(0b0000, 0b0000), 0);
        assert_eq!(hamming(0b1010, 0b0000), 2);
        assert_eq!(hamming(u64::MAX, 0), 64);
    }

    #[test]
    fn dhash_luma8_rejects_size_mismatch() {
        assert!(dhash_luma8(2, 2, &[0, 0, 0]).is_none());
        assert!(dhash_luma8(0, 5, &[]).is_none());
        assert!(dhash_luma8(2, 2, &[1, 2, 3, 4]).is_some());
    }

    #[test]
    fn identical_buffers_hash_identically() {
        // A simple horizontal gradient.
        let w = 16u32;
        let h = 16u32;
        let buf: Vec<u8> = (0..(w * h)).map(|i| (i % 256) as u8).collect();
        let a = dhash_luma8(w, h, &buf).unwrap();
        let b = dhash_luma8(w, h, &buf).unwrap();
        assert_eq!(a, b);
        assert_eq!(hamming(a, b), 0);
    }

    #[test]
    fn group_similar_clusters_near_and_separates_far() {
        // Two near-identical hashes (distance 1) and one far away (distance 32).
        let near_a = 0x0F0F_0F0F_0F0F_0F0Fu64;
        let near_b = near_a ^ 0b1; // distance 1
        let far = 0xF0F0_F0F0_F0F0_F0F0u64; // distance 64 from near_a

        let items = vec![
            item("/a.jpg", near_a),
            item("/b.jpg", near_b),
            item("/c.jpg", far),
        ];
        let groups = group_similar(&items, 5);
        assert_eq!(groups.len(), 1, "only a & b are similar");
        assert_eq!(groups[0], vec!["/a.jpg".to_string(), "/b.jpg".to_string()]);
    }

    #[test]
    fn group_similar_is_transitive() {
        // a~b (d=2), b~c (d=2), a~c (d=4): with max_distance 2, union-find still
        // merges all three because a-b and b-c each fall within range.
        let a = 0u64;
        let b = 0b11u64;
        let c = 0b1100u64;
        let items = vec![item("/a", a), item("/b", b), item("/c", c)];
        let groups = group_similar(&items, 2);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].len(), 3);
    }

    #[test]
    fn group_similar_handles_exact_duplicates() {
        let h = 0xDEAD_BEEF_DEAD_BEEFu64;
        let items = vec![item("/x", h), item("/y", h), item("/z", h)];
        let groups = group_similar(&items, 0);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].len(), 3);
    }
}
