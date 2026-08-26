import XCTest
@testable import MacFanControlCore

final class SMCKeysTests: XCTestCase {
    func testEncodeKey() {
        XCTAssertEqual(SMCKeyCodec.encodeKey("FNum"), 0x464E756D)
        XCTAssertEqual(SMCKeyCodec.encodeKey("F0Md"), 0x46304D64)
    }

    func testModeKeyCandidates() {
        XCTAssertEqual(SMCKeyCodec.modeKeyCandidates(for: 0), ["F0Md", "F0md"])
        XCTAssertEqual(SMCKeyCodec.modeKeyCandidates(for: 1), ["F1Md", "F1md"])
    }

    func testFloatRoundTrip() {
        let original = 4200.0
        let encoded = SMCKeyCodec.encodeFloat(original)
        let decoded = SMCKeyCodec.decodeFloat(from: encoded)
        XCTAssertEqual(decoded, original, accuracy: 0.001)
    }

    func testFPE2RoundTrip() {
        let original = 45.5
        let encoded = SMCKeyCodec.encodeFPE2(original)
        let decoded = SMCKeyCodec.decodeFPE2(from: encoded)
        XCTAssertEqual(decoded, original, accuracy: 0.25)
    }

    func testUI8RoundTrip() {
        let encoded = SMCKeyCodec.encodeUI8(3)
        XCTAssertEqual(SMCKeyCodec.decodeUI8(from: encoded), 3)
    }

    func testComponentName() {
        XCTAssertEqual(SMCKeyCodec.componentName(for: "TC0P"), "CPU")
        XCTAssertEqual(SMCKeyCodec.componentName(for: "TG0P"), "GPU")
        XCTAssertEqual(SMCKeyCodec.componentName(for: "Tp0C"), "CPU")
        XCTAssertEqual(SMCKeyCodec.componentName(for: "Tg0d"), "GPU")
        XCTAssertEqual(SMCKeyCodec.componentName(for: "TH0B"), "Battery")
        XCTAssertEqual(SMCKeyCodec.componentName(for: "TB1T"), "Battery")
        XCTAssertEqual(SMCKeyCodec.componentName(for: "TW0P"), "Wi-Fi")
    }

    func testFriendlySensorNames() {
        XCTAssertEqual(SMCKeyCodec.friendlySensorName(for: "Tp0C"), "CPU")
        XCTAssertEqual(SMCKeyCodec.friendlySensorName(for: "Tg0d"), "GPU Die")
        XCTAssertEqual(SMCKeyCodec.friendlySensorName(for: "TW0P"), "Wi-Fi")
        XCTAssertEqual(SMCKeyCodec.friendlySensorName(for: "TH0B"), "Battery")
        XCTAssertEqual(SMCKeyCodec.friendlySensorName(for: "TB1T"), "Battery")
    }

    func testHelperDaemonPaths() {
        XCTAssertEqual(PrivilegedWriteDaemon.socketPath(for: 501), "/tmp/macfancontrol-501.sock")
        XCTAssertEqual(PrivilegedWriteDaemon.logPath(for: 501), "/tmp/macfancontrol-501.log")
        XCTAssertEqual(PrivilegedWriteDaemon.installedHelperPath, "/usr/local/libexec/MacFanControlHelper")
        XCTAssertEqual(PrivilegedWriteDaemon.launchdLabel, "com.macfancontrol.helper")
    }
}

final class DiagnosticReportTests: XCTestCase {
    func testDiagnosticTextIncludesFanDetails() {
        let profile = HardwareProfile(
            fanCount: 1,
            fanModeKeys: ["F0Md"],
            hasFtstKey: true,
            chipDescription: "Apple M2",
            macOSVersion: "macOS 14.0"
        )

        let fan = Fan(
            id: 0,
            modeKey: "F0Md",
            actualRPM: 1800,
            targetRPM: 2000,
            minRPM: 1200,
            maxRPM: 6200,
            mode: .manual
        )

        let report = DiagnosticExporter.makeReport(
            profile: profile,
            fans: [fan],
            sensors: [],
            readOnly: false,
            notes: ["test note"]
        )

        let text = report.text
        XCTAssertTrue(text.contains("Apple M2"))
        XCTAssertTrue(text.contains("F0Md"))
        XCTAssertTrue(text.contains("test note"))
        XCTAssertTrue(text.contains("Fan helper running"))
    }
}
