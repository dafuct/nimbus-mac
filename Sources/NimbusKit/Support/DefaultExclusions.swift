import Foundation

/// Sensible default scan exclusions. Space Lens is meant to show what's big — so
/// we deliberately keep this narrow: only directories that (a) stall the walk by
/// faulting network/online-only files, or (b) are large transient build/cache
/// trees that aren't user-actionable from a disk map. The user's folder picker
/// bypasses these to inspect anything in full.
public enum DefaultExclusions {

    /// Defaults applied to the Space Lens home scan (merged with the user list).
    public static func spaceLens() -> ExclusionMatcher {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let literals = [
            // Online-only / network-faulting providers — the main cause of stalls.
            "\(home)/Library/CloudStorage",
            "\(home)/Library/Mobile Documents",     // iCloud Drive
            // Large transient system trees.
            "\(home)/Library/Caches",
            "\(home)/Library/Developer/CoreSimulator/Caches",
        ]
        // Transient build trees at any depth.
        let globs = [
            "*/node_modules",
            "*/.build",
            "*/DerivedData",
            "*/Carthage/Build",
        ]
        return ExclusionMatcher(literals: literals, globs: globs)
    }
}
