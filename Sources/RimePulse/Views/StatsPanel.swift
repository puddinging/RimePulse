import ServiceManagement
import SwiftUI

struct StatsPanel: View {
    let reader: StatsReader
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
                TotalStatsView(today: reader.today, history: reader.history)
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
                    .onChange(of: launchAtLogin) { _, newValue in
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
        .frame(width: 196)
    }
}
