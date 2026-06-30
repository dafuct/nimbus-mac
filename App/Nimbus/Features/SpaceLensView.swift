import SwiftUI
import AppKit
import NimbusKit
import NimbusViewModels

/// Space Lens — squarified treemap (pure layout in `TreemapLayout`) with
/// breadcrumbs, a disk gauge, and a detail side panel. Tap a folder to drill in,
/// tap a file to act on it. Skinned to `Nimbus.dc.html`.
struct SpaceLensView: View {
    @Bindable var viewModel: SpaceLensViewModel
    @State private var drillPath: [DiskUsageNode] = []
    @State private var selected: DiskUsageNode?

    var body: some View {
        VStack(spacing: 16) {
            topBar
            mainArea
        }
        .padding(EdgeInsets(top: 20, leading: 28, bottom: 24, trailing: 28))
        .background(Theme.Colors.window)
        .overlay {
            if let report = viewModel.lastRemoval {
                RemovalDoneOverlay(reclaimedBytes: report.reclaimedBytes) { viewModel.dismissReport() }
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 20) {
            breadcrumbs
            Spacer()
            if viewModel.isScanning {
                ProgressView().controlSize(.small)
                Button("Скасувати") { viewModel.cancel() }
            } else {
                Button { pickFolder() } label: { Image(systemName: "folder") }
                    .help("Вибрати теку для аналізу")
                    .accessibilityLabel("Вибрати теку для аналізу")
                Button("Сканувати") { drillPath = []; selected = nil; viewModel.scan() }.keyboardShortcut("r")
            }
            diskGauge
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            crumb(name: rootNode?.name ?? "Macintosh HD", depth: 0)
            ForEach(Array(drillPath.enumerated()), id: \.element.id) { index, node in
                Text("/").foregroundStyle(Theme.Colors.textQuaternary)
                crumb(name: node.name, depth: index + 1)
            }
        }
        .font(Theme.Font.body(13))
    }

    private func crumb(name: String, depth: Int) -> some View {
        Button {
            drillPath = Array(drillPath.prefix(depth))
            selected = nil
        } label: {
            Text(name).foregroundStyle(Theme.Colors.accent).fontWeight(.semibold)
        }
        .buttonStyle(.plain)
    }

    private var diskGauge: some View {
        let d = disk
        return HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 1) {
                Text("Використано").font(Theme.Font.body(11)).foregroundStyle(Theme.Colors.textTertiary)
                Text("\(d.used.formattedBytes) / \(d.total.formattedBytes)").font(Theme.Font.display(14)).foregroundStyle(Theme.Colors.textPrimary)
            }
            VStack(alignment: .trailing, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule().fill(LinearGradient(colors: [Theme.Colors.accentDeep, Theme.Colors.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * d.fraction)
                    }
                }
                .frame(width: 130, height: 7)
                Text("\((d.total - d.used).formattedBytes) вільно").font(Theme.Font.body(10.5)).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    // MARK: Main area

    @ViewBuilder
    private var mainArea: some View {
        switch viewModel.phase {
        case .idle:
            ContentUnavailableView("Скануйте, щоб побачити мапу диску", systemImage: "chart.pie",
                description: Text("Без привілеїв — Space Lens читає вашу домівку."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .scanning(progress):
            VStack(spacing: 8) {
                ProgressView()
                Text("\(progress.filesSeen) файлів · \(progress.bytesSeen.formattedBytes)").foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Сканування не вдалося", systemImage: "exclamationmark.triangle", description: Text(message))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            HStack(spacing: 18) {
                treemap.frame(maxWidth: .infinity)
                detailPanel.frame(width: 300)
            }
        }
    }

    private var treemap: some View {
        GeometryReader { geo in
            let children = currentNode?.children ?? []
            let tiles = TreemapLayout.squarify(
                children.map { (id: $0.id, weight: Double(max($0.size, 1))) },
                in: CGRect(origin: .zero, size: geo.size)
            )
            ZStack(alignment: .topLeading) {
                ForEach(tiles, id: \.id) { tile in
                    if let child = children.first(where: { $0.id == tile.id }) {
                        TreemapTileView(node: child, selected: selected?.id == child.id)
                            .frame(width: max(1, tile.rect.width - 2), height: max(1, tile.rect.height - 2))
                            .offset(x: tile.rect.minX, y: tile.rect.minY)
                            .onTapGesture { tap(child) }
                    }
                }
            }
        }
        .background(Color(hex: 0x0F0F13), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            let node = selected ?? currentNode
            VStack(alignment: .leading, spacing: 8) {
                Text((node?.isDirectory ?? true) ? "ТЕКА" : "ФАЙЛ / ГРУПА")
                    .font(Theme.Font.body(11, .semibold)).tracking(0.6).foregroundStyle(Theme.Colors.textQuaternary)
                Text(node?.name ?? "—").font(Theme.Font.body(17, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                Text(node?.size.formattedBytes ?? "—").font(Theme.Font.display(32)).foregroundStyle(Theme.Colors.accentLight)
                if let node, !node.isDirectory {
                    VStack(spacing: 8) {
                        Button("Перемістити в Кошик") { Task { await viewModel.trash(node) } }
                            .buttonStyle(.plain).frame(maxWidth: .infinity).modifier(LensPrimary())
                        Button("Показати у Finder") { reveal(node.url) }
                            .buttonStyle(.plain).frame(maxWidth: .infinity).modifier(LensSecondary())
                    }
                    .padding(.top, 8)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nimbusCard()

            Text("Натисніть на блок, щоб заглибитись у теку, або оберіть файл, щоб діяти з ним. Розмір блоку = розмір на диску.")
                .font(Theme.Font.body(12.5)).foregroundStyle(Theme.Colors.textSecondary).lineSpacing(2)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surfaceFainter, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))

            Spacer()
        }
    }

    // MARK: Helpers

    private var rootNode: DiskUsageNode? {
        if case let .loaded(root) = viewModel.phase { return root }
        return nil
    }
    private var currentNode: DiskUsageNode? { drillPath.last ?? rootNode }

    private func tap(_ node: DiskUsageNode) {
        if node.isDirectory && !node.children.isEmpty {
            drillPath.append(node)
            selected = nil
        } else {
            selected = node
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Аналізувати"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setRoot(url)
            drillPath = []
            selected = nil
            viewModel.scan()
        }
    }

    private var disk: (fraction: Double, used: Int64, total: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let vals = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Int64(vals?.volumeTotalCapacity ?? 0)
        let avail = vals?.volumeAvailableCapacityForImportantUsage ?? 0
        let used = max(0, total - Int64(avail))
        return (total > 0 ? Double(used) / Double(total) : 0, used, total)
    }
}

private struct TreemapTileView: View {
    let node: DiskUsageNode
    let selected: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(Theme.Colors.treemapTile(for: node.name))
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).font(Theme.Font.body(12.5, .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(node.size.formattedBytes).font(Theme.Font.display(11.5, .medium)).foregroundStyle(.white.opacity(0.78))
            }
            .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(selected ? .white.opacity(0.85) : Theme.Colors.window.opacity(0.6), lineWidth: selected ? 1.5 : 1)
        )
        .clipped()
        .help("\(node.name) — \(node.size.formattedBytes)")
    }
}

private struct LensPrimary: ViewModifier {
    func body(content: Content) -> some View {
        content.font(Theme.Font.body(13, .semibold)).foregroundStyle(.white)
            .padding(10).background(Theme.Gradients.accentButton, in: RoundedRectangle(cornerRadius: 10))
    }
}
private struct LensSecondary: ViewModifier {
    func body(content: Content) -> some View {
        content.font(Theme.Font.body(13, .semibold)).foregroundStyle(Theme.Colors.textControl)
            .padding(10).background(Theme.Colors.surfaceFaint, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
    }
}
