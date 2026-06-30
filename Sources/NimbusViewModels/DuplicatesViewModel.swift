import Foundation
import Observation
import NimbusKit

/// Drives the Duplicates screen: scan via the injected Rust-backed hasher, manage
/// the shared selection, and remove through the shared `Remover` (Trash by
/// default; permanent needs explicit confirmation).
@MainActor
@Observable
public final class DuplicatesViewModel {
    public enum Phase: Sendable {
        case idle
        case scanning(ScanProgress)
        case loaded([DuplicateGroup])
        case failed(String)
    }

    public enum PhotoPhase: Sendable {
        case idle
        case scanning(ScanProgress)
        case loaded([SimilarPhotoGroup])
        case failed(String)
    }

    public enum Tab: Sendable { case files, photos }
    public var tab: Tab = .files

    public private(set) var phase: Phase = .idle
    public private(set) var selection = SelectionStore<DuplicateFile>()
    public private(set) var photoPhase: PhotoPhase = .idle
    public private(set) var photoSelection = SelectionStore<SimilarPhoto>()
    public var roots: [URL]
    public var minFileSize: Int64
    public var exclusions: ExclusionMatcher
    public private(set) var lastRemoval: RemovalReport?

    private let scanner: DuplicateScanner
    private let photoScanner: SimilarPhotoScanner
    private let remover: Remover
    private var scanTask: Task<Void, Never>?
    private var photoTask: Task<Void, Never>?

    public init(
        hasher: ContentHashing,
        perceptualHasher: PerceptualHashing,
        roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser],
        minFileSize: Int64 = 4 * 1024,
        exclusions: ExclusionMatcher = .empty,
        remover: Remover = Remover()
    ) {
        self.scanner = DuplicateScanner(hasher: hasher)
        self.photoScanner = SimilarPhotoScanner(hasher: perceptualHasher)
        self.roots = roots
        self.minFileSize = minFileSize
        self.exclusions = exclusions
        self.remover = remover
    }

    public var groups: [DuplicateGroup] {
        if case let .loaded(groups) = phase { return groups }
        return []
    }

    public var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    public var reclaimableSelected: Int64 {
        selection.reclaimableBytes(over: groups.flatMap(\.files))
    }

    public func scan() {
        cancel()
        scanTask = Task { [weak self] in await self?.performScan() }
    }

    /// The awaitable scan body (used by `scan()` and exercised directly in tests).
    func performScan() async {
        phase = .scanning(.zero)
        do {
            let groups = try await scanner.findDuplicates(
                roots: roots, minFileSize: minFileSize, exclusions: exclusions
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    if case .scanning = self?.phase { self?.phase = .scanning(progress) }
                }
            }
            phase = .loaded(groups)
            selectSmartDefault()
        } catch let error as NimbusError where error.isCancellation {
            phase = .idle
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func cancel() {
        scanTask?.cancel()
        scanTask = nil
    }

    /// Keep one copy per group, pre-select the rest.
    public func selectSmartDefault() {
        selection.selectAllButFirst(in: groups) { $0.files }
    }

    public func toggle(_ file: DuplicateFile) { selection.toggle(file.id) }
    public func clearSelection() { selection.clear() }

    /// Remove selected duplicates. `permanently == false` ⇒ Trash (reversible).
    public func removeSelected(permanently: Bool = false) async {
        let items = selection
            .selectedItems(from: groups.flatMap(\.files))
            .map { RemovalItem(url: $0.url, bytes: $0.removalBytes) }
        guard !items.isEmpty else { return }
        let report = await remover.remove(
            items,
            mode: permanently ? .permanentDelete : .trash,
            allowPermanent: permanently
        )
        lastRemoval = report
        clearSelection()
        scan() // refresh
    }

    // MARK: - Similar photos

    public var photoGroups: [SimilarPhotoGroup] {
        if case let .loaded(groups) = photoPhase { return groups }
        return []
    }

    public var isScanningPhotos: Bool {
        if case .scanning = photoPhase { return true }
        return false
    }

    public var photoReclaimableSelected: Int64 {
        photoSelection.reclaimableBytes(over: photoGroups.flatMap(\.photos))
    }

    public func scanPhotos() {
        photoTask?.cancel()
        photoTask = Task { [weak self] in await self?.performPhotoScan() }
    }

    func performPhotoScan() async {
        photoPhase = .scanning(.zero)
        do {
            let groups = try await photoScanner.findSimilar(roots: roots, exclusions: exclusions) { [weak self] progress in
                Task { @MainActor [weak self] in
                    if case .scanning = self?.photoPhase { self?.photoPhase = .scanning(progress) }
                }
            }
            photoPhase = .loaded(groups)
            photoSelectSmartDefault()
        } catch let error as NimbusError where error.isCancellation {
            photoPhase = .idle
        } catch is CancellationError {
            photoPhase = .idle
        } catch {
            photoPhase = .failed(error.localizedDescription)
        }
    }

    public func cancelPhotos() { photoTask?.cancel(); photoTask = nil }

    /// Keep the largest photo in each series, select the rest.
    public func photoSelectSmartDefault() {
        var store = SelectionStore<SimilarPhoto>()
        for group in photoGroups {
            let sorted = group.photos.sorted { $0.size > $1.size }
            for photo in sorted.dropFirst() { store.set(photo.id, selected: true) }
        }
        photoSelection = store
    }

    public func togglePhoto(_ photo: SimilarPhoto) { photoSelection.toggle(photo.id) }

    public func isBestPhoto(_ photo: SimilarPhoto, in group: SimilarPhotoGroup) -> Bool {
        (group.photos.max { $0.size < $1.size })?.id == photo.id
    }

    public func removeSelectedPhotos(permanently: Bool = false) async {
        let items = photoSelection.selectedItems(from: photoGroups.flatMap(\.photos))
            .map { RemovalItem(url: $0.url, bytes: $0.removalBytes) }
        guard !items.isEmpty else { return }
        lastRemoval = await remover.remove(items, mode: permanently ? .permanentDelete : .trash, allowPermanent: permanently)
        photoSelection.clear()
        scanPhotos()
    }
}
