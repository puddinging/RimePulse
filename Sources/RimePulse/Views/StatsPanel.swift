import ServiceManagement
import SwiftUI

struct StatsPanel: View {
    static let fixedPanelWidth: CGFloat = 286

    let reader: StatsReader
    /// 初始值为 false；真实状态在 `.task` 中异步读取，避免首次打开菜单栏时
    /// `SMAppService.mainApp.status` 的同步 XPC 调用阻塞首帧。
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let today = reader.today {
                TodayStatsView(stats: today)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.title2)
                        .foregroundStyle(.quaternary)
                    Text("暂无今日数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            if !reader.history.isEmpty {
                Divider()
                    .padding(.horizontal, 10)
                HistoryListView(history: reader.history)
                    .padding(.vertical, 6)
            }

            if !reader.history.isEmpty || reader.today != nil {
                Divider()
                    .padding(.horizontal, 10)
                TotalStatsView(today: reader.today, trendDaily: reader.trendDaily)
                    .padding(.vertical, 6)
            }

            Divider()
                .padding(.horizontal, 10)

            HStack {
                Toggle("开机启动", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .tint(Color(nsColor: .controlAccentColor))
                    .onChange(of: launchAtLogin) { _, newValue in
                        // 幂等保护：`.task` 首次同步状态时会翻转 launchAtLogin，
                        // 此时 SMAppService 真实状态已与新值一致，跳过写入。
                        let currentlyEnabled = SMAppService.mainApp.status == .enabled
                        guard newValue != currentlyEnabled else { return }
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("退出")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: Self.fixedPanelWidth)
        .task {
            // 同步 launchd 状态：让首次构建面板时不用等同步 XPC。
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
