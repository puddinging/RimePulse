import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        // 禁止系统自动终止，menu bar app 没有窗口但需要常驻
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar app must stay alive")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
