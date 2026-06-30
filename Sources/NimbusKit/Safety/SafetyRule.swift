import Foundation

/// Matches paths by base directory + glob patterns, with tilde expansion. Unlike
/// `ExclusionMatcher` (which answers "should I skip this?"), this answers "does
/// this rule apply here?".
public struct PathMatcher: Sendable, Equatable {
    /// Glob patterns (absolute, tilde-allowed) tested with `fnmatch`.
    public let globs: [String]

    public init(globs: [String]) {
        self.globs = globs.map { PathCanonical.firmlink(($0 as NSString).expandingTildeInPath) }
    }

    public func matches(_ url: URL) -> Bool {
        let path = PathCanonical.firmlink(url.path)
        // FNM_PATHNAME: `*` matches within a single path segment, so patterns are
        // precise (e.g. `.../Resources/*.lproj` matches a language folder, not its
        // contents). Cleanup evaluates item-level paths, which this expects.
        for glob in globs where fnmatch(glob, path, FNM_PATHNAME) == 0 { return true }
        return false
    }
}

/// One declarative safety rule. Nothing imperative: a rule describes *where* it
/// applies, *when* (OS range + required app), and the *disposition* it confers.
/// The catalog is a list of these; the engine just evaluates them.
public struct SafetyRule: Sendable, Identifiable {
    public let id: String
    public let category: CleanupCategory
    public let disposition: SafetyDisposition
    public let reason: String
    public let matcher: PathMatcher
    /// Applies only on macOS ≥ this version (nil = no lower bound).
    public let minOS: OSVersion?
    /// Applies only on macOS ≤ this version (nil = no upper bound).
    public let maxOS: OSVersion?
    /// Applies only when this bundle id is installed (nil = always).
    public let requiresApp: String?

    public init(
        id: String,
        category: CleanupCategory,
        disposition: SafetyDisposition,
        reason: String,
        matcher: PathMatcher,
        minOS: OSVersion? = nil,
        maxOS: OSVersion? = nil,
        requiresApp: String? = nil
    ) {
        self.id = id
        self.category = category
        self.disposition = disposition
        self.reason = reason
        self.matcher = matcher
        self.minOS = minOS
        self.maxOS = maxOS
        self.requiresApp = requiresApp
    }

    func isActive(on os: OSVersion, installedApps: Set<String>) -> Bool {
        if let minOS, os < minOS { return false }
        if let maxOS, os > maxOS { return false }
        if let requiresApp, !installedApps.contains(requiresApp) { return false }
        return true
    }
}
