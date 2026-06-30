import Foundation

/// The concrete, curated rule set. This is the heart of "safe by construction":
/// every removable area is enumerated here with an explicit disposition, reason,
/// and (where relevant) OS/app gating. Anything not listed is protected by the
/// engine's default-deny.
///
/// Real products grow this catalog continuously and ship it as data (so it can
/// update without an app release). The selection below is representative, not
/// exhaustive, and deliberately errs toward caution: anything that could hold
/// user-authored or shippable artifacts is `.selectableManually`, never auto.
public enum SafetyCatalog {

    public static func standard() -> [SafetyRule] {
        [
            // ---- User caches: generally safe to clear; apps rebuild them. ----
            SafetyRule(
                id: "user.caches",
                category: .userCaches,
                disposition: .autoSelectable,
                reason: "App caches are regenerated automatically when needed.",
                matcher: PathMatcher(globs: ["~/Library/Caches/*"])
            ),
            // Exception: iOS device backups live nowhere near Caches, but CloudKit
            // and container-manager state under Caches can be costly to rebuild —
            // demote to manual as a per-area exception (stricter wins).
            SafetyRule(
                id: "user.caches.cloudkit",
                category: .userCaches,
                disposition: .selectableManually,
                reason: "CloudKit caches can be expensive to re-sync — review first.",
                matcher: PathMatcher(globs: ["~/Library/Caches/CloudKit*", "~/Library/Caches/com.apple.cloudkit*"])
            ),

            // ---- Logs ----
            SafetyRule(
                id: "user.logs",
                category: .systemLogs,
                disposition: .autoSelectable,
                reason: "Diagnostic logs are safe to remove.",
                matcher: PathMatcher(globs: ["~/Library/Logs/*"])
            ),

            // ---- Trash ----
            SafetyRule(
                id: "user.trash",
                category: .trash,
                disposition: .autoSelectable,
                reason: "Items already in the Trash.",
                matcher: PathMatcher(globs: ["~/.Trash/*"])
            ),

            // ---- Xcode / developer junk (only when Xcode is installed) ----
            SafetyRule(
                id: "xcode.derivedData",
                category: .xcodeJunk,
                disposition: .autoSelectable,
                reason: "Derived data is rebuilt on next build.",
                matcher: PathMatcher(globs: ["~/Library/Developer/Xcode/DerivedData/*"]),
                requiresApp: "com.apple.dt.Xcode"
            ),
            SafetyRule(
                id: "xcode.deviceSupport",
                category: .xcodeJunk,
                disposition: .selectableManually,
                reason: "Re-downloaded when you next debug on that iOS version.",
                matcher: PathMatcher(globs: ["~/Library/Developer/Xcode/iOS DeviceSupport/*"]),
                requiresApp: "com.apple.dt.Xcode"
            ),
            SafetyRule(
                id: "xcode.archives",
                category: .xcodeJunk,
                disposition: .selectableManually,
                reason: "Archives may contain builds you still need to ship — review first.",
                matcher: PathMatcher(globs: ["~/Library/Developer/Xcode/Archives/*"]),
                requiresApp: "com.apple.dt.Xcode"
            ),
            SafetyRule(
                id: "coresimulator.caches",
                category: .xcodeJunk,
                disposition: .autoSelectable,
                reason: "Simulator caches are regenerated.",
                matcher: PathMatcher(globs: ["~/Library/Developer/CoreSimulator/Caches/*"]),
                requiresApp: "com.apple.dt.Xcode"
            ),

            // ---- Mail downloads ----
            SafetyRule(
                id: "mail.downloads",
                category: .mailAttachments,
                disposition: .selectableManually,
                reason: "Saved Mail attachments — you may still want some.",
                matcher: PathMatcher(globs: [
                    "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/*"
                ])
            ),

            // ---- App language files: removing these can break apps; never auto. ----
            SafetyRule(
                id: "app.languages",
                category: .languageFiles,
                disposition: .selectableManually,
                reason: "Removing localizations frees space but can break an app’s UI.",
                matcher: PathMatcher(globs: ["/Applications/*.app/Contents/Resources/*.lproj"])
            ),

            // ---- Per-OS example: QuickLook thumbnail cache path differs by release ----
            SafetyRule(
                id: "quicklook.thumbnails.legacy",
                category: .userCaches,
                disposition: .autoSelectable,
                reason: "Thumbnail cache, regenerated on demand (pre-Tahoe path).",
                matcher: PathMatcher(globs: ["~/Library/Caches/com.apple.QuickLook.thumbnailcache/*"]),
                maxOS: OSVersion(25, .max, .max)
            ),
            SafetyRule(
                id: "quicklook.thumbnails.tahoe",
                category: .userCaches,
                disposition: .autoSelectable,
                reason: "Thumbnail cache, regenerated on demand (Tahoe+ path).",
                matcher: PathMatcher(globs: ["~/Library/Caches/com.apple.quicklook.ThumbnailsAgent/*"]),
                minOS: .tahoe
            ),

            // ---- Protected example: never offer iOS device backups for removal ----
            SafetyRule(
                id: "protect.iosBackups",
                category: .appLeftovers,
                disposition: .protected,
                reason: "iOS device backups are irreplaceable — never removed.",
                matcher: PathMatcher(globs: ["~/Library/Application Support/MobileSync/Backup/*"])
            ),
        ]
    }
}
