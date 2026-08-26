import XCTest
@testable import MacFanControlCore

final class ThermalPressureTests: XCTestCase {
    func testNotifyStateMapping() {
        XCTAssertEqual(ThermalPressure.from(state: 0), .nominal)
        XCTAssertEqual(ThermalPressure.from(state: 1), .moderate)
        XCTAssertEqual(ThermalPressure.from(state: 2), .heavy)
        XCTAssertEqual(ThermalPressure.from(state: 3), .trapping)
        XCTAssertEqual(ThermalPressure.from(state: 4), .sleeping)
        XCTAssertEqual(ThermalPressure.from(state: 99), .unknown)
    }

    func testLabels() {
        XCTAssertEqual(ThermalPressure.nominal.label, "Nominal")
        XCTAssertEqual(ThermalPressure.moderate.label, "Moderate")
        XCTAssertEqual(ThermalPressure.heavy.label, "Heavy")
        XCTAssertEqual(ThermalPressure.trapping.label, "Trapping")
    }
}

final class FanCurveTests: XCTestCase {
    func testLerpsBetween65And85() {
        let minRPM = 2317.0
        let maxRPM = 6550.0

        XCTAssertEqual(FanCurve.targetRPM(temperature: 50, minRPM: minRPM, maxRPM: maxRPM), minRPM)
        XCTAssertEqual(FanCurve.targetRPM(temperature: 65, minRPM: minRPM, maxRPM: maxRPM), minRPM)
        XCTAssertEqual(FanCurve.targetRPM(temperature: 85, minRPM: minRPM, maxRPM: maxRPM), maxRPM)
        XCTAssertEqual(FanCurve.targetRPM(temperature: 95, minRPM: minRPM, maxRPM: maxRPM), maxRPM)

        let mid = FanCurve.targetRPM(temperature: 75, minRPM: minRPM, maxRPM: maxRPM)
        XCTAssertEqual(mid, (minRPM + maxRPM) / 2, accuracy: 0.01)
    }

    func testNeverCommandsBelowMinRPM() {
        let rpm = FanCurve.targetRPM(temperature: 20, minRPM: 2317, maxRPM: 6550)
        XCTAssertGreaterThanOrEqual(rpm, 2317)
    }

    func testHottestDieUsesCPUAndGPUOnly() {
        let sensors = [
            TemperatureSensor(id: "Tp0C", name: "CPU Die", component: "CPU", celsius: 72),
            TemperatureSensor(id: "Tg0d", name: "GPU Die", component: "GPU", celsius: 81),
            TemperatureSensor(id: "TB0T", name: "Battery", component: "Battery", celsius: 40)
        ]
        XCTAssertEqual(FanCurve.hottestDieCelsius(in: sensors), 81)
    }

    func testControlModeBadges() {
        XCTAssertEqual(ControlMode.appleAuto.badgeLabel, "Auto")
        XCTAssertEqual(ControlMode.performanceCurve.badgeLabel, "Performance")
        XCTAssertEqual(ControlMode.fixedRPM.badgeLabel, "Manual")
    }
}

final class TemperatureSummaryTests: XCTestCase {
    func testKeepsHottestOfEachComponent() {
        let sensors = [
            TemperatureSensor(id: "Tp0C", name: "CPU Die", component: "CPU", celsius: 71),
            TemperatureSensor(id: "Tp09", name: "CPU Virtual Die", component: "CPU", celsius: 74),
            TemperatureSensor(id: "Tg0d", name: "GPU Die", component: "GPU", celsius: 68),
            TemperatureSensor(id: "Tg0p", name: "GPU Proximity", component: "GPU", celsius: 61),
            TemperatureSensor(id: "TB0T", name: "Battery 1", component: "Battery", celsius: 38),
            TemperatureSensor(id: "TB1T", name: "Battery 2", component: "Battery", celsius: 41),
            TemperatureSensor(id: "TW0P", name: "Wi-Fi Module", component: "Wi-Fi", celsius: 52),
            TemperatureSensor(id: "TH0x", name: "NAND", component: "NAND", celsius: 44)
        ]
        let summary = TemperatureSummary.hottestByComponent(sensors)
        XCTAssertEqual(summary.map(\.component), ["CPU", "GPU", "Battery", "Wi-Fi"])
        XCTAssertEqual(summary[0].celsius, 74)
        XCTAssertEqual(summary[1].celsius, 68)
        XCTAssertEqual(summary[2].celsius, 41)
        XCTAssertEqual(summary[3].celsius, 52)
    }
}

final class HistoryBufferTests: XCTestCase {
    func testCapsAtEightMinutes() {
        var samples: [HistorySample] = []
        for index in 0..<500 {
            samples = HistoryBuffer.appending(
                samples,
                HistorySample(
                    time: Date(timeIntervalSince1970: Double(index)),
                    cpuCelsius: 70,
                    gpuCelsius: 60,
                    fanRPM: 3000,
                    pressure: .nominal
                )
            )
        }
        XCTAssertEqual(samples.count, HistoryBuffer.capacity)
        XCTAssertEqual(HistoryBuffer.capacity, 480)
        XCTAssertEqual(samples.first?.time, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(samples.last?.time, Date(timeIntervalSince1970: 499))
    }
}
