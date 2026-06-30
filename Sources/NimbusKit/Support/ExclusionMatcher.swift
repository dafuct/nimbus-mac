import Foundation

/// A `Sendable`, value-type predicate over paths, shared by every scanner so the
/// user-editable exclusion list is honored uniformly (Space Lens, Duplicates,
/// Cleanup, Uninstaller all consult the same matcher — no per-module copies).
///
/// Matching rules, checked against each entry's full POSIX path:
/// - `literals`: exact path or any descendant of it.
/// - `globs`: shell-style `*`/`?`/`[...]` patterns via `fnmatch`.
public struct ExclusionMatcher: Sendable, Equatable {
    public private(set) var literals: [String]
    public private(set) var globs: [String]

    public init(literals: [String] = [], globs: [String] = []) {
        // Literals are canonicalized once (symlinks/firmlinks resolved) so a
        // single cheap string comparison suffices per scanned entry — scanners
        // already emit canonical paths, so we don't pay a stat per check.
        self.literals = literals.map { Self.canonical($0) }
        self.globs = globs
    }

    public static let empty = ExclusionMatcher()

    public func shouldExclude(_ url: URL) -> Bool {
        shouldExclude(path: url.path)
    }

    public func shouldExclude(path raw: String) -> Bool {
        let path = Self.normalize(raw)
        for literal in literals {
            if path == literal || path.hasPrefix(literal + "/") {
                return true
            }
        }
        for glob in globs {
            if fnmatch(glob, path, 0) == 0 {
                return true
            }
        }
        return false
    }

    public func adding(literal path: String) -> ExclusionMatcher {
        ExclusionMatcher(literals: literals + [path], globs: globs)
    }

    /// Combine two matchers (e.g. default scan exclusions + the user's list).
    public func merging(_ other: ExclusionMatcher) -> ExclusionMatcher {
        ExclusionMatcher(literals: literals + other.literals, globs: globs + other.globs)
    }

    /// Fully canonical form (tilde + symlinks + firmlink) — used once per literal.
    static func canonical(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let resolved = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
        return PathCanonical.firmlink(resolved)
    }

    /// Cheap form for the hot per-entry path: tilde, trailing slash, firmlink.
    /// No filesystem access — `contentsOfDirectory` already emits `/private/var…`,
    /// so we only need to normalize that firmlink to compare against literals.
    private static func normalize(_ path: String) -> String {
        var p = (path as NSString).expandingTildeInPath
        if p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return PathCanonical.firmlink(p)
    }
}
