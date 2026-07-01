import SwiftUI
import NimbusKit
import NimbusViewModels

/// Duplicates — the Swift→Rust showcase, with Files (exact, BLAKE3) and Photos
/// (perceptual dHash) tabs. Skinned to `Nimbus.dc.html`. Expressions are split
/// into small typed subviews to keep the type-checker stable.
struct DuplicatesView: View {
    @Environment(Localizer.self) private var loc
    @Bindable var viewModel: DuplicatesViewModel
    @State private var permanently = false
    @State private var confirmingPermanent = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Colors.hairlineSoft)
            content
            Divider().overlay(Theme.Colors.hairlineSoft)
            footer
        }
        .background(Theme.Colors.window)
        .confirmationDialog(
            loc("Видалити вибране остаточно? Дію не можна скасувати."),
            isPresented: $confirmingPermanent, titleVisibility: .visible
        ) {
            Button(loc("Видалити остаточно"), role: .destructive) {
                Task {
                    if viewModel.tab == .files { await viewModel.removeSelected(permanently: true) }
                    else { await viewModel.removeSelectedPhotos(permanently: true) }
                }
            }
            Button(loc("Скасувати"), role: .cancel) {}
        }
        .overlay {
            if let report = viewModel.lastRemoval {
                RemovalDoneOverlay(reclaimedBytes: report.reclaimedBytes) { /* cleared on next scan */ }
            }
        }
    }

    // MARK: Header (tabs + hint + action)

    private var header: some View {
        HStack(spacing: 14) {
            tabs
            actionButton
            Spacer()
            autoHint
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
    }

    private var tabs: some View {
        HStack(spacing: 3) {
            tabButton(loc("Дублікати файлів"), .files)
            tabButton(loc("Схожі фото"), .photos)
        }
        .padding(3)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
    }

    private func tabButton(_ label: String, _ tab: DuplicatesViewModel.Tab) -> some View {
        let active = viewModel.tab == tab
        return Button { viewModel.tab = tab } label: {
            Text(label).font(Theme.Font.body(13, .semibold))
                .foregroundStyle(active ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .padding(.vertical, 7).padding(.horizontal, 16)
                .background(active ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var actionButton: some View {
        if viewModel.tab == .files {
            if viewModel.isScanning {
                ProgressView().controlSize(.small); Button(loc("Скасувати")) { viewModel.cancel() }
            } else {
                Button(loc("Знайти")) { viewModel.scan() }.keyboardShortcut("r")
            }
        } else {
            if viewModel.isScanningPhotos {
                ProgressView().controlSize(.small); Button(loc("Скасувати")) { viewModel.cancelPhotos() }
            } else {
                Button(loc("Знайти")) { viewModel.scanPhotos() }.keyboardShortcut("r")
            }
        }
    }

    private var autoHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 12))
            Text(loc("Авто-вибір залишає найкращу копію")).font(Theme.Font.body(12))
        }
        .foregroundStyle(Theme.Colors.accentLight)
        .padding(.vertical, 7).padding(.horizontal, 13)
        .background(Theme.Colors.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if viewModel.tab == .files { filesContent } else { photosContent }
    }

    @ViewBuilder
    private var filesContent: some View {
        switch viewModel.phase {
        case .idle:
            ContentUnavailableView(loc("Знайдіть дублікати файлів"), systemImage: "doc.on.doc",
                description: Text(loc("Сканує домівку, потім звіряє схожі файли в Rust для точного збігу.")))
        case .scanning:
            scanningView(loc("%lld файлів перевірено", filesProgress))
        case .failed(let message):
            ContentUnavailableView(loc("Сканування не вдалося"), systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded:
            if viewModel.groups.isEmpty {
                ContentUnavailableView(loc("Дублікатів не знайдено"), systemImage: "checkmark.seal")
            } else {
                // Lazy layout: `List` builds an identity node for *every* row up front
                // (OutlineListCoordinator.diffRows), which overflowed AttributeGraph on
                // large scans and aborted. LazyVStack only realizes on-screen rows. The
                // render cap is belt-and-suspenders; selection/removal still run over the
                // full `viewModel.groups`, so auto-select keeps working for hidden groups.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.groups.prefix(maxVisibleGroups)) { group in
                            Section { fileRows(group) } header: { fileHeader(group) }
                        }
                        if viewModel.groups.count > maxVisibleGroups { truncationNote }
                    }
                    .padding(EdgeInsets(top: 12, leading: 28, bottom: 18, trailing: 28))
                }
            }
        }
    }

    /// Hard ceiling on rows fed to the view tree, regardless of scan size.
    private let maxVisibleGroups = 500

    private var truncationNote: some View {
        Text(loc("Показано %lld з %lld груп — звузьте область сканування, щоб побачити решту",
                 maxVisibleGroups, viewModel.groups.count))
            .font(Theme.Font.body(11.5))
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.top, 10)
    }

    private var filesProgress: Int {
        if case let .scanning(p) = viewModel.phase { return p.filesSeen }
        return 0
    }

    private func fileHeader(_ group: NimbusKit.DuplicateGroup) -> some View {
        HStack {
            Text(loc("%lld копій · %@ кожна", group.files.count, group.fileSize.formattedBytes))
            Spacer()
            Text(loc("Звільнити %@", group.reclaimableBytes.formattedBytes)).foregroundStyle(Theme.Colors.accentLight)
        }
        .font(Theme.Font.body(11.5))
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.top, 12).padding(.bottom, 2)
    }

    private func fileRows(_ group: NimbusKit.DuplicateGroup) -> some View {
        ForEach(group.files, id: \.id) { file in
            DuplicateFileRow(file: file,
                             isSelected: viewModel.selection.isSelected(file.id),
                             onToggle: { viewModel.toggle(file) })
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var photosContent: some View {
        switch viewModel.photoPhase {
        case .idle:
            ContentUnavailableView(loc("Знайдіть схожі фото"), systemImage: "photo.on.rectangle.angled",
                description: Text(loc("Perceptual-хешування (Rust) групує візуально схожі знімки.")))
        case .scanning:
            scanningView(loc("Хешування фото…"))
        case .failed(let message):
            ContentUnavailableView(loc("Сканування не вдалося"), systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded:
            if viewModel.photoGroups.isEmpty {
                ContentUnavailableView(loc("Схожих фото не знайдено"), systemImage: "checkmark.seal")
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(viewModel.photoGroups.enumerated()), id: \.element.id) { index, group in
                            PhotoSeriesCard(index: index, group: group, viewModel: viewModel)
                        }
                    }
                    .padding(EdgeInsets(top: 18, leading: 28, bottom: 18, trailing: 28))
                }
            }
        }
    }

    private func scanningView(_ text: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            ProgressView()
            Text(text).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(loc("Видаляти остаточно"), isOn: $permanently).toggleStyle(.switch).tint(Theme.Colors.accent)
            Spacer()
            Text(loc("%lld вибрано · %@", selectedCount, selectedReclaim.formattedBytes))
                .font(Theme.Font.body(12)).foregroundStyle(Theme.Colors.textSecondary)
            removeButton
        }
        .padding(.horizontal, 28).padding(.vertical, 15)
        .background(Color(hex: 0x0F0F13).opacity(0.6))
    }

    private var selectedCount: Int {
        viewModel.tab == .files ? viewModel.selection.count : viewModel.photoSelection.count
    }
    private var selectedReclaim: Int64 {
        viewModel.tab == .files ? viewModel.reclaimableSelected : viewModel.photoReclaimableSelected
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            if permanently {
                confirmingPermanent = true
            } else {
                Task {
                    if viewModel.tab == .files { await viewModel.removeSelected() }
                    else { await viewModel.removeSelectedPhotos() }
                }
            }
        } label: {
            Label(permanently ? loc("Видалити…") : loc("Перемістити в Кошик"), systemImage: "trash")
        }
        .disabled(selectedCount == 0)
    }
}

// MARK: - Rows / cards

private struct DuplicateFileRow: View {
    let file: DuplicateFile
    let isSelected: Bool
    let onToggle: () -> Void
    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent).lineLimit(1)
                Text(file.url.deletingLastPathComponent().path)
                    .font(Theme.Font.mono(11)).foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .toggleStyle(.checkbox)
    }
}

private struct PhotoSeriesCard: View {
    @Environment(Localizer.self) private var loc
    let index: Int
    let group: SimilarPhotoGroup
    @Bindable var viewModel: DuplicatesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("Серія %lld", index + 1)).font(Theme.Font.body(14, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(loc("%lld фото · %lld до видалення", group.photos.count, group.photos.count - 1))
                        .font(Theme.Font.body(11.5)).foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                Text(group.reclaimableBytes.formattedBytes).font(Theme.Font.display(15)).foregroundStyle(Theme.Colors.accentLighter)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 11) {
                    ForEach(group.photos, id: \.id) { photo in
                        PhotoTile(
                            photo: photo,
                            isBest: viewModel.isBestPhoto(photo, in: group),
                            isSelected: viewModel.photoSelection.isSelected(photo.id),
                            onToggle: { viewModel.togglePhoto(photo) }
                        )
                    }
                }
            }
        }
        .padding(16)
        .nimbusCard()
    }
}

private struct PhotoTile: View {
    @Environment(Localizer.self) private var loc
    let photo: SimilarPhoto
    let isBest: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ThumbnailImage(url: photo.url, maxPixel: 256)
                .frame(width: 152, height: 114)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .frame(width: 152, height: 114)
            if isBest {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 9))
                    Text(loc("Залишити")).font(Theme.Font.body(10.5, .semibold))
                }
                .foregroundStyle(.white)
                .padding(.vertical, 3).padding(.horizontal, 8)
                .background(Theme.Colors.accent.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                .padding(7)
            } else {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18)).foregroundStyle(isSelected ? Theme.Colors.accent : .white.opacity(0.85))
                        .background(Circle().fill(.black.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .frame(width: 152).padding(7)
            }
            VStack {
                Spacer()
                HStack {
                    Text(photo.url.lastPathComponent).font(Theme.Font.body(10)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    Spacer()
                    Text(photo.size.formattedBytes).font(Theme.Font.mono(10)).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
            }
            .frame(width: 152, height: 114)
        }
        .frame(width: 152, height: 114)
    }
}
