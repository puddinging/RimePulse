import SwiftUI

@main
struct RimeStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var reader = StatsReader()

    var body: some Scene {
        MenuBarExtra {
            StatsPanel(reader: reader)
        } label: {
            StatusBarLabel(stats: reader.today)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}
