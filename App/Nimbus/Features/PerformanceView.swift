import SwiftUI
import NimbusViewModels

/// Performance — maintenance tasks + a read-only list of launch agents/daemons.
/// Skinned to `Nimbus.dc.html`.
struct PerformanceView: View {
    @Bindable var viewModel: PerformanceViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if !viewModel.helperInstalled { helperBanner }
                tasksCard
                agentsCard
            }
            .padding(EdgeInsets(top: 26, leading: 28, bottom: 40, trailing: 28))
        }
        .background(Theme.Colors.window)
        .task { viewModel.load() }
    }

    private var helperBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: "lock.shield").foregroundStyle(Theme.Colors.accentLight)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Привілейовані задачі потребують помічника").font(Theme.Font.body(13, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text("Очищення DNS і переіндексація Spotlight виконуються root-демоном через SMAppService.")
                        .font(Theme.Font.body(11.5)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Button("Увімкнути") { Task { await viewModel.installHelper() } }
                    .buttonStyle(.plain).modifier(PrimaryButtonM())
            }
            if let message = viewModel.helperMessage {
                Text(message).font(Theme.Font.body(11.5)).foregroundStyle(Theme.Colors.warning)
            }
        }
        .padding(16)
        .background(Theme.Colors.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.Colors.accent.opacity(0.16), lineWidth: 0.5))
    }

    private var tasksCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Задачі обслуговування").font(Theme.Font.body(16, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text("Безпечні операції, які macOS зазвичай виконує сама. Запустіть вручну за потреби.")
                        .font(Theme.Font.body(12.5)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Button(runLabel) { Task { await viewModel.runSelected() } }
                    .buttonStyle(.plain).modifier(PrimaryButtonM())
                    .disabled(viewModel.selectedCount == 0 || viewModel.isRunning)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.hairlineSoft).frame(height: 0.5) }

            ForEach(viewModel.tasks) { task in
                TaskRow(task: task) { viewModel.toggle(task.id) }
                    .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.hairlineSoft).frame(height: 0.5) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nimbusCard()
    }

    private var runLabel: String {
        if viewModel.isRunning { return "Виконання…" }
        return "Запустити обрані · \(viewModel.selectedCount)"
    }

    private var agentsCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Елементи входу та фонові процеси").font(Theme.Font.body(16, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text("Запускаються разом із системою. Керування — у Системних налаштуваннях.")
                        .font(Theme.Font.body(12.5)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Виявлено").font(Theme.Font.body(11)).foregroundStyle(Theme.Colors.textTertiary)
                    Text("\(viewModel.slowAgentCount)").font(Theme.Font.display(18)).foregroundStyle(Theme.Colors.warning)
                }
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.hairlineSoft).frame(height: 0.5) }

            // App's own launch-at-login — the one we can actually toggle.
            HStack(spacing: 13) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nimbus під час входу").font(Theme.Font.body(13.5, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text("Єдиний елемент, яким Nimbus керує напряму.").font(Theme.Font.body(11)).foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $viewModel.appLaunchAtLogin).labelsHidden().toggleStyle(.switch).tint(Theme.Colors.accent)
            }
            .padding(.horizontal, 20).padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.hairlineSoft).frame(height: 0.5) }

            ForEach(viewModel.agents) { agent in
                AgentRow(agent: agent)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.hairlineSoft).frame(height: 0.5) }
            }

            HStack {
                Spacer()
                Button("Відкрити в Системних налаштуваннях") { viewModel.openLoginItemsSettings() }
                    .buttonStyle(.plain)
                    .font(Theme.Font.body(13, .semibold)).foregroundStyle(Theme.Colors.textControl)
                    .padding(.vertical, 9).padding(.horizontal, 16)
                    .background(Theme.Colors.surfaceFaint, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nimbusCard()
    }
}

private struct PrimaryButtonM: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.body(13.5, .semibold)).foregroundStyle(.white)
            .padding(.vertical, 11).padding(.horizontal, 18)
            .background(Theme.Gradients.accentButton, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TaskRow: View {
    let task: PerformanceViewModel.TaskItem
    let onToggle: () -> Void
    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: task.selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(task.selected ? Theme.Colors.accent : Theme.Colors.textTertiary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(task.name).font(Theme.Font.body(13.5, .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                        if task.recommended {
                            Badge(text: "рекомендовано", color: Theme.Colors.success)
                        }
                        statusView
                    }
                    Text(task.desc).font(Theme.Font.body(12)).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Text(task.estimate).font(Theme.Font.mono(11)).foregroundStyle(Theme.Colors.textQuaternary).padding(.top, 2)
            }
            .padding(.vertical, 14).padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var statusView: some View {
        switch task.status {
        case .idle: EmptyView()
        case .running: ProgressView().controlSize(.mini)
        case .done:
            Label("виконано", systemImage: "checkmark").labelStyle(.titleAndIcon)
                .font(Theme.Font.body(10.5, .semibold)).foregroundStyle(Theme.Colors.success)
        case .failed(let msg):
            Text(msg).font(Theme.Font.body(10.5)).foregroundStyle(Theme.Colors.warning).lineLimit(1)
        }
    }
}

private struct AgentRow: View {
    let agent: PerformanceViewModel.AgentItem
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "gearshape.2").font(.system(size: 13)).foregroundStyle(Theme.Colors.textTertiary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name).font(Theme.Font.body(13)).foregroundStyle(Theme.Colors.textBright).lineLimit(1)
                Text(agent.source).font(Theme.Font.body(11)).foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(Theme.Font.body(9.5, .semibold)).foregroundStyle(color)
            .padding(.vertical, 2).padding(.horizontal, 7)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
    }
}
