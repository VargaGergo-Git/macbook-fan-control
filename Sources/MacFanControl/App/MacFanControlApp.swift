import SwiftUI
import AppKit
import MacFanControlCore

@main
struct MacFanControlApp: App {
    @StateObject private var controller = FanController()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("MacFanControl", systemImage: "fanblades.fill") {
            FanControlView(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}
