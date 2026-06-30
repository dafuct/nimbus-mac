import Foundation
import Observation
import NimbusKit
import NimbusViewModels

/// Composition root: builds shared services once and hands dependencies to view
/// models. Injected into the SwiftUI environment. This is where the Rust-backed
/// hashers and the privileged-helper client are wired in.
@MainActor
@Observable
final class AppEnvironment {
    var exclusionList: ExclusionList
    let installedApps: Set<String>
    let osVersion: OSVersion
    @ObservationIgnored let localizer = Localizer()

    @ObservationIgnored let contentHasher: ContentHashing = RustContentHasher()
    @ObservationIgnored let perceptualHasher: PerceptualHashing = RustPerceptualHasher()
    // Real XPC-backed helper. Privileged ops degrade gracefully (throw) until the
    // helper is installed/approved — which needs a Developer ID-signed build.
    @ObservationIgnored let helper: PrivilegedHelperClient = XPCHelperClient()

    init() {
        exclusionList = ExclusionList.load(from: ExclusionList.defaultURL)
        installedApps = InstalledAppsProvider().installedBundleIDs()
        osVersion = .current
    }

    // Long-lived view models, created once and observed by the feature views
    // directly (not through the environment, hence @ObservationIgnored — also
    // required because @Observable forbids `lazy` stored properties).
    @ObservationIgnored lazy var smartScan = SmartScanViewModel(engine: safetyEngine())
    @ObservationIgnored lazy var spaceLens = SpaceLensViewModel(exclusions: exclusionList.matcher)
    @ObservationIgnored lazy var duplicates = DuplicatesViewModel(hasher: contentHasher, perceptualHasher: perceptualHasher, exclusions: exclusionList.matcher)
    @ObservationIgnored lazy var cleanup = CleanupViewModel(engine: safetyEngine())
    @ObservationIgnored lazy var health = HealthViewModel()
    @ObservationIgnored lazy var settings = SettingsViewModel()
    @ObservationIgnored lazy var uninstaller = UninstallerViewModel()
    @ObservationIgnored lazy var performance = PerformanceViewModel(helper: helper)

    func safetyEngine() -> SafetyRuleEngine {
        SafetyRuleEngine(
            // Data-driven: a user JSON override at SafetyCatalog.defaultURL wins,
            // else the built-in catalog.
            rules: SafetyCatalog.rules(),
            exclusions: exclusionList.matcher,
            osVersion: osVersion,
            installedApps: installedApps
        )
    }

    func persistExclusions() {
        try? FileManager.default.createDirectory(
            at: ExclusionList.defaultURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? exclusionList.save(to: ExclusionList.defaultURL)
    }
}
