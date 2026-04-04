import SwiftUI

private struct LabelWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@main
struct RimeStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var reader = StatsReader()
    @State private var labelWidth: CGFloat = 0

    var body: some Scene {
        MenuBarExtra {
            StatsPanel(reader: reader, labelWidth: labelWidth)
        } label: {
            Text(StatusBarLabel.format(stats: reader.today))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: LabelWidthKey.self, value: geo.size.width)
                    }
                )
                .onPreferenceChange(LabelWidthKey.self) { width in
                    labelWidth = width
                }
        }
        .menuBarExtraStyle(.window)
    }
}
