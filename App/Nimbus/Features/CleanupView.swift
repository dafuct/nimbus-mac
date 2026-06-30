import SwiftUI
import NimbusKit
import NimbusViewModels

/// Cleanup — expandable category cards from the safety engine. Auto-selectable
/// categories are pre-ticked and badged "Безпечно"; manual ones "Перевірте" and
/// start unticked. Skinned to `Nimbus.dc.html`.
struct CleanupView: View {
    @Bindable var viewModel: CleanupViewModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Colors.hairlineSoft)
            content
            Divider().overlay(Theme.Colors.hairlineSoft)
            footer
        }
        .background(Theme.Colors.window)
        .confirmationDialog("Перемістити вибране в Кошик?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Перемістити в Кошик") { Task { await viewModel.removeSelected() } }
            Button("Скасувати", role: .cancel) {}
        } message: {
            Text("Файли не зникнуть одразу — їх можна відновити з Кошика.")
        }
        .overlay {
            if let report = viewModel.lastRemoval {
                RemovalDoneOverlay(reclaimedBytes: report.reclaimedBytes) { viewModel.dismissReport() }
            }
        }
    }

    private var header: some View {
        HStack {
            if case .scanning = viewModel.phase {
                ProgressView().controlSize(.small)
                Button("Скасувати") { viewModel.cancel() }
            } else {
                Button("Сканувати") { viewModel.scan() }.keyboardShortcut("r")
            }
            Spacer()
            safetyHint
        }
        .padding(Theme.Spacing.md)
    }

    private var safetyHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward").font(.system(size: 11))
            Text("Усе видаляється в Кошик · «Перевірте» залишаємо невибраним").font(Theme.Font.body(12))
        }
        .foregroundStyle(Theme.Colors.accentLight)
        .padding(.vertical, 7).padding(.horizontal, 13)
        .background(Theme.Colors.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            ContentUnavailableView("Скануйте, щоб знайти мотлох", systemImage: "sparkles",
                description: Text("Кеші, логи, Xcode-сміття та інше — лише з відомо-безпечних шляхів."))
        case .scanning:
            VStack(spacing: 8) { ProgressView(); Text("Сканування…").foregroundStyle(Theme.Colors.textSecondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Сканування не вдалося", systemImage: "exclamationmark.triangle", description: Text(message))
        case let .loaded(groups):
            if groups.isEmpty {
                ContentUnavailableView("Нічого прибирати", systemImage: "checkmark.seal")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(groups) { group in
                            CategoryCard(group: group, viewModel: viewModel)
                        }
                    }
                    .padding(EdgeInsets(top: 18, leading: 28, bottom: 18, trailing: 28))
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("До переміщення в Кошик").font(Theme.Font.body(12)).foregroundStyle(Theme.Colors.textTertiary)
                Text("\(viewModel.reclaimableSelected.formattedBytes) · \(viewModel.selection.count) елементів")
                    .font(Theme.Font.display(21)).foregroundStyle(Theme.Colors.textPrimary)
            }
            Spacer()
            Button { confirming = true } label: {
                Label("Перемістити в Кошик", systemImage: "trash")
            }
            .buttonStyle(.plain).modifier(TrashButton(enabled: !viewModel.selection.isEmpty))
            .disabled(viewModel.selection.isEmpty)
        }
        .padding(.horizontal, 28).padding(.vertical, 15)
        .background(Color(hex: 0x0F0F13).opacity(0.6))
    }
}

private struct TrashButton: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.body(14, .semibold)).foregroundStyle(.white)
            .padding(.vertical, 12).padding(.horizontal, 22)
            .background(enabled ? AnyShapeStyle(Theme.Gradients.accentButton) : AnyShapeStyle(Color.white.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct CategoryCard: View {
    let group: CleanupGroup
    @Bindable var viewModel: CleanupViewModel

    private var isSafe: Bool { group.items.allSatisfy(\.autoSelected) }
    private var expanded: Bool { viewModel.isExpanded(group) }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.items, id: \.id) { item in
                        ItemRow(item: item, selected: viewModel.selection.isSelected(item.id)) {
                            viewModel.toggle(item)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .nimbusCard(radius: 13)
    }

    private var headerRow: some View {
        HStack(spacing: 13) {
            Button { viewModel.toggleCategory(group) } label: {
                TriCheckbox(state: viewModel.selectionState(group))
            }
            .buttonStyle(.plain)

            Image(systemName: "folder").font(.system(size: 14)).foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(group.category.rawValue).font(Theme.Font.body(14, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(isSafe ? "Безпечно" : "Перевірте")
                        .font(Theme.Font.body(10, .semibold))
                        .foregroundStyle(isSafe ? Theme.Colors.success : Theme.Colors.warning)
                        .padding(.vertical, 2).padding(.horizontal, 7)
                        .background((isSafe ? Theme.Colors.success : Theme.Colors.warning).opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
                }
                Text("\(viewModel.selectedCount(in: group)) / \(group.items.count) вибрано")
                    .font(Theme.Font.body(11.5)).foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer()
            Text(group.totalBytes.formattedBytes).font(Theme.Font.display(15)).foregroundStyle(Theme.Colors.accentLighter)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.Colors.textQuaternary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { viewModel.toggleExpand(group) } }
    }
}

private struct ItemRow: View {
    let item: CleanupItem
    let selected: Bool
    let onToggle: () -> Void
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ItemCheckbox(selected: selected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.url.lastPathComponent).font(Theme.Font.body(13, .medium)).foregroundStyle(Theme.Colors.textBright).lineLimit(1)
                    Text(item.url.path).font(Theme.Font.mono(11)).foregroundStyle(Theme.Colors.textQuaternary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(item.bytes.formattedBytes).font(Theme.Font.mono(12)).foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.vertical, 9).padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TriCheckbox: View {
    let state: CleanupViewModel.GroupSelection
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(state == .none ? AnyShapeStyle(Color.white.opacity(0.04)) : AnyShapeStyle(Theme.Gradients.accentButton))
                .frame(width: 20, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(state == .none ? Color.white.opacity(0.2) : .clear, lineWidth: 1))
            switch state {
            case .all: Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            case .some: Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            case .none: EmptyView()
            }
        }
    }
}

private struct ItemCheckbox: View {
    let selected: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? AnyShapeStyle(Theme.Gradients.accentButton) : AnyShapeStyle(Color.white.opacity(0.04)))
                .frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selected ? .clear : Color.white.opacity(0.2), lineWidth: 1))
            if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
        }
    }
}
