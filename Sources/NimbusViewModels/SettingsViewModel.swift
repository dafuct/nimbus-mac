import Foundation
import Observation
import NimbusKit

/// Drives the Settings screen. Toggles persist to `UserDefaults`; the exclusion
/// list persists through `ExclusionList` (honored by every scan); launch-at-login
/// is real via `LoginItemsService`.
@MainActor
@Observable
public final class SettingsViewModel {
    public enum DuplicateDepth: String, Sendable, CaseIterable { case fast, normal, deep }

    // General
    public var menuBarEnabled: Bool { didSet { persist(\.menuBarEnabled, "menuBarEnabled") } }
    public var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }

    // Scan & safety
    public var safeDelete: Bool { didSet { persist(\.safeDelete, "safeDelete") } }
    public var scanMail: Bool { didSet { persist(\.scanMail, "scanMail") } }
    public var duplicateDepth: DuplicateDepth { didSet { defaults.set(duplicateDepth.rawValue, forKey: "dupDepth") } }

    // Smart Scan modules
    public var moduleCleanup: Bool { didSet { persist(\.moduleCleanup, "mCleanup") } }
    public var moduleLens: Bool { didSet { persist(\.moduleLens, "mLens") } }
    public var moduleDuplicates: Bool { didSet { persist(\.moduleDuplicates, "mDup") } }
    public var moduleUninstaller: Bool { didSet { persist(\.moduleUninstaller, "mUninstall") } }
    public var modulePerformance: Bool { didSet { persist(\.modulePerformance, "mPerf") } }

    // Exclusions (persisted to ExclusionList.defaultURL)
    public private(set) var exclusions: [String]
    public var newExclusionInput: String = ""

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let loginItems = LoginItemsService()

    public init() {
        let d = UserDefaults.standard
        menuBarEnabled = d.object(forKey: "menuBarEnabled") as? Bool ?? true
        safeDelete = d.object(forKey: "safeDelete") as? Bool ?? true
        scanMail = d.object(forKey: "scanMail") as? Bool ?? false
        duplicateDepth = DuplicateDepth(rawValue: d.string(forKey: "dupDepth") ?? "") ?? .normal
        moduleCleanup = d.object(forKey: "mCleanup") as? Bool ?? true
        moduleLens = d.object(forKey: "mLens") as? Bool ?? true
        moduleDuplicates = d.object(forKey: "mDup") as? Bool ?? true
        moduleUninstaller = d.object(forKey: "mUninstall") as? Bool ?? true
        modulePerformance = d.object(forKey: "mPerf") as? Bool ?? true
        exclusions = ExclusionList.load(from: ExclusionList.defaultURL).paths
        launchAtLogin = LoginItemsService().launchAtLoginState() == .enabled
    }

    public func addExclusion() {
        let trimmed = newExclusionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = ExclusionList.load(from: ExclusionList.defaultURL)
        list.add(path: trimmed)
        persistExclusions(list)
        newExclusionInput = ""
    }

    public func removeExclusion(_ path: String) {
        var list = ExclusionList.load(from: ExclusionList.defaultURL)
        list.remove(path: path)
        persistExclusions(list)
    }

    public func openLoginItemsSettings() { loginItems.openLoginItemsSettings() }

    // MARK: - Private

    private func persist<T>(_ keyPath: KeyPath<SettingsViewModel, T>, _ key: String) {
        defaults.set(self[keyPath: keyPath], forKey: key)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try loginItems.enableLaunchAtLogin() }
            else { try loginItems.disableLaunchAtLogin() }
        } catch {
            // Revert UI if the OS refused; SMAppService needs a proper signed build.
        }
    }

    private func persistExclusions(_ list: ExclusionList) {
        try? FileManager.default.createDirectory(
            at: ExclusionList.defaultURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? list.save(to: ExclusionList.defaultURL)
        exclusions = list.paths
    }
}
