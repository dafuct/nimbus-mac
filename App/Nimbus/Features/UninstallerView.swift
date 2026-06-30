import SwiftUI
import NimbusKit
import NimbusViewModels

/// Uninstaller — installed apps on the left, the selected app's full removal set
/// (bundle + `~/Library` leftovers) on the right. Skinned to `Nimbus.dc.html`.
struct UninstallerView: View {
    @Bindable var viewModel: UninstallerViewModel

    var body: some View {
        HStack(spacing: 0) {
            masterList.frame(width: 360)
            Divider().overlay(Theme.Colors.hairline)
            detail.frame(maxWidth: .infinity)
        }
        .background(Theme.Colors.window)
        .task { if viewModel.rows.isEmpty { viewModel.load() } }
    }

    // MARK: Master list

    private var masterList: some View {
        VStack(spacing: 0) {
            VStack(spacing: 11) {
                searchField
                filterButtons
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 12, trailing: 18))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredRows) { row in
                        AppRowView(row: row, selected: row.id == viewModel.selectedID) {
                            Task { await viewModel.select(row.id) }
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 12)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Theme.Colors.textTertiary)
            TextField("Пошук застосунків", text: $viewModel.query)
                .textFieldStyle(.plain).font(Theme.Font.body(13)).foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.vertical, 9).padding(.horizontal, 12)
        .background(Theme.Colors.surfaceFaint, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
    }

    private var filterButtons: some View {
        HStack(spacing: 6) {
            filterChip("Усі \(viewModel.total)", .all)
            filterChip("Рідко вживані \(viewModel.rareCount)", .rare)
            filterChip("За розміром", .large)
            Spacer()
        }
    }

    private func filterChip(_ label: String, _ filter: UninstallerViewModel.Filter) -> some View {
        let active = viewModel.filter == filter
        return Button { viewModel.filter = filter } label: {
            Text(label).font(Theme.Font.body(12, .semibold))
                .foregroundStyle(active ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(active ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let row = viewModel.selectedRow {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        detailHeader(row)
                        if row.isRare { rareWarning }
                        Text("ЩО БУДЕ ВИДАЛЕНО").font(Theme.Font.body(11, .semibold)).tracking(0.7)
                            .foregroundStyle(Theme.Colors.textQuaternary).padding(.top, 24).padding(.bottom, 11)
                        removalList(row)
                        Text("Звичайне перетягування в Кошик залишає приховані файли. Nimbus прибирає їх разом із застосунком.")
                            .font(Theme.Font.body(12)).foregroundStyle(Theme.Colors.textTertiary).padding(.top, 12)
                    }
                    .padding(EdgeInsets(top: 26, leading: 28, bottom: 20, trailing: 28))
                }
                detailFooter
            }
        } else {
            ContentUnavailableView("Оберіть застосунок", systemImage: "macwindow")
        }
    }

    private func detailHeader(_ row: UninstallerViewModel.Row) -> some View {
        HStack(spacing: 16) {
            AppAvatar(initials: row.initials, bundleID: row.app.bundleID, size: 62, radius: 15, fontSize: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.app.name).font(Theme.Font.display(23)).foregroundStyle(Theme.Colors.textPrimary)
                Text("Останнє відкриття: \(usedText(row.lastUsed))")
                    .font(Theme.Font.body(12.5)).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
    }

    private var rareWarning: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.Colors.warning)
            Text("Ви давно не відкривали цей застосунок. Видалення безпечне — за потреби його можна перевстановити.")
                .font(Theme.Font.body(12.5)).foregroundStyle(Color(hex: 0xD8C99A))
        }
        .padding(.vertical, 11).padding(.horizontal, 14)
        .background(Theme.Colors.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.Colors.warning.opacity(0.16), lineWidth: 0.5))
        .padding(.top, 18)
    }

    private func removalList(_ row: UninstallerViewModel.Row) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.leftovers.enumerated()), id: \.element.id) { index, leftover in
                if index > 0 { Divider().overlay(Theme.Colors.hairlineSoft) }
                LeftoverRowView(
                    leftover: leftover,
                    selected: viewModel.selection.isSelected(leftover.id),
                    onToggle: { viewModel.toggle(leftover) }
                )
            }
        }
        .nimbusCard()
    }

    private var detailFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("До переміщення в Кошик").font(Theme.Font.body(12)).foregroundStyle(Theme.Colors.textTertiary)
                Text(viewModel.selectedTotal.formattedBytes).font(Theme.Font.display(21)).foregroundStyle(Theme.Colors.textPrimary)
            }
            Spacer()
            Button("Видалити повністю") { Task { await viewModel.uninstall() } }
                .buttonStyle(.plain)
                .modifier(PrimaryButton())
                .disabled(viewModel.selection.isEmpty)
        }
        .padding(.horizontal, 28).padding(.vertical, 15)
        .background(Color(hex: 0x0F0F13).opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.hairline).frame(height: 0.5) }
    }

    private func usedText(_ date: Date?) -> String {
        guard let date else { return "невідомо" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 1 { return "сьогодні" }
        if days < 30 { return "\(days) дн тому" }
        let months = days / 30
        if months < 12 { return "\(months) міс тому" }
        return "\(months / 12) р тому"
    }
}

private struct PrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.body(14, .semibold)).foregroundStyle(.white)
            .padding(.vertical, 12).padding(.horizontal, 22)
            .background(Theme.Gradients.accentButton, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct AppAvatar: View {
    let initials: String
    let bundleID: String
    var size: CGFloat = 38
    var radius: CGFloat = 10
    var fontSize: CGFloat = 13
    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Theme.Colors.treemapTile(for: bundleID))
            .frame(width: size, height: size)
            .overlay(Text(initials).font(Theme.Font.display(fontSize, .bold)).foregroundStyle(.white))
    }
}

private struct AppRowView: View {
    let row: UninstallerViewModel.Row
    let selected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AppAvatar(initials: row.initials, bundleID: row.app.bundleID)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(row.app.name).font(Theme.Font.body(13.5, .semibold)).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                        if row.isRare {
                            Text("рідко").font(Theme.Font.body(9, .semibold)).foregroundStyle(Theme.Colors.warning)
                                .padding(.vertical, 1.5).padding(.horizontal, 6)
                                .background(Theme.Colors.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    Text(row.app.version.map { "v\($0)" } ?? row.app.bundleID)
                        .font(Theme.Font.body(11)).foregroundStyle(Theme.Colors.textTertiary).lineLimit(1)
                }
                Spacer()
                Text(row.sizeBytes.map { $0.formattedBytes } ?? "…")
                    .font(Theme.Font.display(13)).foregroundStyle(Theme.Colors.accentLighter)
            }
            .padding(.vertical, 10).padding(.horizontal, 11)
            .background(selected ? Color.white.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LeftoverRowView: View {
    let leftover: Leftover
    let selected: Bool
    let onToggle: () -> Void
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Theme.Colors.accent : Theme.Colors.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(leftover.kind.rawValue).font(Theme.Font.body(13, .medium)).foregroundStyle(Theme.Colors.textBright)
                    Text(leftover.url.path).font(Theme.Font.mono(11)).foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(leftover.bytes.formattedBytes).font(Theme.Font.mono(12)).foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.vertical, 11).padding(.horizontal, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
