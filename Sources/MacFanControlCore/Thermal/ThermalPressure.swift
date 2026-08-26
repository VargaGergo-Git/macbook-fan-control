import Foundation

/// Firmware thermal pressure from `thermald` via notifyd.
/// This is more useful than `ProcessInfo.thermalState`, which collapses
/// moderate and heavy into a single `fair` value on Apple Silicon.
public enum ThermalPressure: Int, Sendable, Equatable {
    case nominal = 0
    case moderate = 1
    case heavy = 2
    case trapping = 3
    case sleeping = 4
    case unknown = -1

    public var label: String {
        switch self {
        case .nominal: return "Nominal"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        case .trapping: return "Trapping"
        case .sleeping: return "Sleeping"
        case .unknown: return "Unknown"
        }
    }

    public static func from(state: UInt64) -> ThermalPressure {
        ThermalPressure(rawValue: Int(state)) ?? .unknown
    }
}

#if os(macOS)
/// Xcode 27 Darwin overlay does not export notify(3). Bind the C symbols directly.
@_silgen_name("notify_register_check")
private func darwinNotifyRegisterCheck(_ name: UnsafePointer<CChar>, _ token: UnsafeMutablePointer<Int32>) -> UInt32

@_silgen_name("notify_get_state")
private func darwinNotifyGetState(_ token: Int32, _ state: UnsafeMutablePointer<UInt64>) -> UInt32

@_silgen_name("notify_cancel")
private func darwinNotifyCancel(_ token: Int32) -> UInt32
#endif

final class ThermalPressureMonitor {
    #if os(macOS)
    private var token: Int32 = 0
    private var registered = false
    #endif

    func start() {
        #if os(macOS)
        guard !registered else { return }
        let name = "com.apple.system.thermalpressurelevel"
        let status = name.withCString { darwinNotifyRegisterCheck($0, &token) }
        registered = status == 0
        #endif
    }

    func current() -> ThermalPressure {
        #if os(macOS)
        if !registered { start() }
        guard registered else { return .unknown }
        var state: UInt64 = 0
        guard darwinNotifyGetState(token, &state) == 0 else { return .unknown }
        return ThermalPressure.from(state: state)
        #else
        return .unknown
        #endif
    }

    func stop() {
        #if os(macOS)
        if registered {
            _ = darwinNotifyCancel(token)
            registered = false
        }
        #endif
    }
}
