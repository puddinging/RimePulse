import AppKit
import Charts
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var prewarmWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar app must stay alive")

        // 应用启动稳定后，在后台预热菜单栏首次打开时才会加载的重型组件：
        // Swift Charts framework、liquid glass shader、ServiceManagement XPC。
        // 这样首次点击菜单栏时，SwiftUI + Metal + launchd 都已处于热状态。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.prewarmFirstOpenCosts()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func prewarmFirstOpenCosts() {
        // 触发 launchd XPC，`SMAppService.mainApp.status` 首次调用最慢。
        _ = SMAppService.mainApp.status

        // 屏外隐藏窗口承载一个最小化的 Chart + glassEffect，
        // 让 Charts dyld / Metal shader / GlassEffect runtime 全部初始化。
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.level = .statusBar
        window.contentView = NSHostingView(rootView: PrewarmView())
        window.orderFrontRegardless()
        prewarmWindow = window

        // 留一秒让 GPU 着色器真正编译完成，然后释放。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.prewarmWindow?.orderOut(nil)
            self?.prewarmWindow = nil
        }
    }
}

private struct PrewarmView: View {
    var body: some View {
        ZStack {
            Chart {
                BarMark(x: .value("x", 0), y: .value("y", 1))
                LineMark(x: .value("x", 0), y: .value("y", 1))
            }
            .frame(width: 120, height: 60)

            GlassEffectContainer(spacing: 0) {
                Text(" ")
                    .padding(4)
                    .glassEffect(.regular, in: Capsule())
            }
        }
    }
}
