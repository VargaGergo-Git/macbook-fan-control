import AppKit
import SwiftUI
import Combine
import MacFanControlCore

@main
enum MacFanControlMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Follow System Settings appearance (Light / Dark / Auto).
        app.appearance = nil
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = FanController()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        installStatusItem()
        bindStatusItemTitle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.releaseAllFans()
        controller.stop()
    }

    private func installStatusItem() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = nil // inherit Light/Dark from System Settings
        popover.contentSize = NSSize(width: 400, height: 820)
        popover.contentViewController = NSHostingController(
            rootView: FanControlView(controller: controller)
                .preferredColorScheme(nil)
        )
        self.popover = popover

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: "MacFanControl")
            button.image?.isTemplate = true
            button.toolTip = "MacFanControl"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func bindStatusItemTitle() {
        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        // Also refresh on a timer so the title stays live while the popover is closed.
        Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        refreshStatusItem()
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        if let die = FanCurve.hottestDieCelsius(in: controller.sensors) {
            button.title = String(format: " %.0f°", die)
            button.toolTip = String(
                format: "MacFanControl — die %.0f °C · %@",
                die,
                controller.controlMode.badgeLabel
            )
        } else {
            button.title = ""
            button.toolTip = "MacFanControl"
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            closePopover()
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        popover?.performClose(nil)
    }
}
