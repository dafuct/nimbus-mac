import Foundation

/// Path canonicalization shared by every path-matching component (exclusions,
/// safety rules, the critical-path guard). Single source of truth so the
/// `/private` firmlink quirk is handled identically everywhere.
public enum PathCanonical {
    /// `/private/var|tmp|etc/…` and `/var|tmp|etc/…` denote the same files via an
    /// APFS firmlink the path-resolution APIs don't collapse. Normalize to the
    /// short form so both sides of any comparison agree. Pure string op — no I/O.
    public static func firmlink(_ path: String) -> String {
        guard path.hasPrefix("/private/") else { return path }
        let rest = String(path.dropFirst("/private".count)) // keep leading slash
        if rest.hasPrefix("/var") || rest.hasPrefix("/tmp") || rest.hasPrefix("/etc") {
            return rest
        }
        return path
    }
}
