import SwiftUI
import AppKit
import MacFanControlCore

@main
struct MacFanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let controller = FanController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        setupStatusItem()
        setupTerminationHandler()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.releaseAllFans()
        controller.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: "MacFanControl")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: FanControlView(controller: controller)
        )

        self.popover = popover
    }

    private func setupTerminationHandler() {
        signal(SIGINT) { _ in
            NSApplication.shared.terminate(nil)
        }
        signal(SIGTERM) { _ in
            NSApplication.shared.terminate(nil)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}
