import SwiftUI
import AppKit
import MacFanControlCore

@main
struct MacFanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = FanController()

    var body: some Scene {
        MenuBarExtra("MacFanControl", systemImage: "fanblades.fill") {
            FanControlView(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
