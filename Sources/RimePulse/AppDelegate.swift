import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let reader = StatsReader()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var statusHostingView: NSHostingView<StatusBarRootView>?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar app must stay alive")
        setupStatusItem()
        setupPopover()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        reader.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.title = ""
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        let hostingView = ClickThroughHostingView(rootView: StatusBarRootView(reader: reader))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        statusHostingView = hostingView
        statusItem = item
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let hosting = NSHostingController(rootView: StatsPanel(reader: reader))
        popover.contentViewController = hosting
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        if let contentView = popover.contentViewController?.view {
            let fitting = contentView.fittingSize
            if fitting.width > 0 && fitting.height > 0 {
                popover.contentSize = fitting
            }
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startPopoverMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        stopPopoverMonitors()
    }

    private func startPopoverMonitors() {
        stopPopoverMonitors()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard self.popover.isShown else { return event }

            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem?.button?.window

            // 点击到弹层外或状态栏外时强制收起
            if event.window !== popoverWindow, event.window !== statusWindow {
                self.popover.performClose(nil)
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            guard self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    private func stopPopoverMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }
}

private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct StatusBarRootView: View {
    let reader: StatsReader

    var body: some View {
        StatusBarLabel(stats: reader.today)
    }
}
