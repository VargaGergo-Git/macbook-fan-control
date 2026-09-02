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
    }
}

final class FanCurveTests: XCTestCase {
    func testPerformanceLerpsOnPro() {
        let chassis = ChassisProfile(kind: .macBookPro, modelIdentifier: "MacBookPro18,1", fanCount: 2)
        let minRPM = 2317.0
        let maxRPM = 6550.0

        XCTAssertEqual(
            FanCurve.targetRPM(temperature: 50, minRPM: minRPM, maxRPM: maxRPM, preset: .performance, chassis: chassis),
            minRPM
        )
        XCTAssertEqual(
            FanCurve.targetRPM(temperature: 65, minRPM: minRPM, maxRPM: maxRPM, preset: .performance, chassis: chassis),
            minRPM
        )
        XCTAssertEqual(
            FanCurve.targetRPM(temperature: 85, minRPM: minRPM, maxRPM: maxRPM, preset: .performance, chassis: chassis),
            maxRPM
        )

        let mid = FanCurve.targetRPM(
            temperature: 75,
            minRPM: minRPM,
            maxRPM: maxRPM,
            preset: .performance,
            chassis: chassis
        )
        XCTAssertEqual(mid, (minRPM + maxRPM) / 2, accuracy: 0.01)
    }

    func testAirQuietUsesSofterCeiling() {
        let air = ChassisProfile(kind: .macBookAir, modelIdentifier: "Mac15,12", fanCount: 1)
        let pro = ChassisProfile(kind: .macBookPro, modelIdentifier: "MacBookPro18,1", fanCount: 2)
        let minRPM = 2000.0
        let maxRPM = 6000.0

        let airQuiet = FanCurve.targetRPM(
            temperature: 95,
            minRPM: minRPM,
            maxRPM: maxRPM,
            preset: .quiet,
            chassis: air
        )
        let proPerf = FanCurve.targetRPM(
            temperature: 95,
            minRPM: minRPM,
            maxRPM: maxRPM,
            preset: .performance,
            chassis: pro
        )

        XCTAssertEqual(airQuiet, minRPM + (maxRPM - minRPM) * 0.82, accuracy: 0.01)
        XCTAssertEqual(proPerf, maxRPM, accuracy: 0.01)
        XCTAssertLessThan(air.ramp(for: .performance).start, pro.ramp(for: .performance).start)
    }

    func testHottestDieFallsBackWhenNoCPUOrGPU() {
        let sensors = [
            TemperatureSensor(id: "TB0T", name: "Battery", component: "Battery", celsius: 40),
            TemperatureSensor(id: "TW0P", name: "Wi-Fi", component: "Wi-Fi", celsius: 52)
        ]
        XCTAssertEqual(FanCurve.hottestDieCelsius(in: sensors), 52)
    }

    func testControlModeBadgesAndPresets() {
        XCTAssertEqual(ControlMode.appleAuto.badgeLabel, "Auto")
        XCTAssertEqual(ControlMode.quietCurve.badgeLabel, "Quiet")
        XCTAssertEqual(ControlMode.balancedCurve.badgeLabel, "Balanced")
        XCTAssertEqual(ControlMode.performanceCurve.badgeLabel, "Performance")
        XCTAssertEqual(ControlMode.curve(.quiet), .quietCurve)
        XCTAssertEqual(ControlMode.quietCurve.curvePreset, .quiet)
    }
}


    func testCurveSamplesAreMonotonicOnRamp() {
        let chassis = ChassisProfile(kind: .macBookPro, modelIdentifier: "MacBookPro18,1", fanCount: 2)
        let samples = FanCurve.curveSamples(
            minRPM: 2000,
            maxRPM: 6000,
            preset: .balanced,
            chassis: chassis,
            fromTemperature: 50,
            toTemperature: 95,
            step: 5
        )
        XCTAssertGreaterThan(samples.count, 5)
        let rpms = samples.map(\.rpm)
        for (a, b) in zip(rpms, rpms.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b + 0.01)
        }
    }

final class TemperatureSummaryTests: XCTestCase {
    func testKeepsHottestOfEachComponent() {
        let sensors = [
            TemperatureSensor(id: "Tp0C", name: "CPU Die", component: "CPU", celsius: 71),
            TemperatureSensor(id: "Tp09", name: "CPU Virtual Die", component: "CPU", celsius: 74),
            TemperatureSensor(id: "Tg0d", name: "GPU Die", component: "GPU", celsius: 68),
            TemperatureSensor(id: "TB0T", name: "Battery 1", component: "Battery", celsius: 38),
            TemperatureSensor(id: "TB1T", name: "Battery 2", component: "Battery", celsius: 41),
            TemperatureSensor(id: "TW0P", name: "Wi-Fi Module", component: "Wi-Fi", celsius: 52),
            TemperatureSensor(id: "TH0x", name: "NAND", component: "Storage", celsius: 44)
        ]
        let summary = TemperatureSummary.hottestByComponent(sensors)
        XCTAssertEqual(summary.map(\.component), ["CPU", "GPU", "Battery", "Wi-Fi"])
        XCTAssertEqual(summary[0].celsius, 74)
        XCTAssertEqual(summary[2].celsius, 41)
    }

    func testFallsBackWhenPreferredComponentsMissing() {
        let sensors = [
            TemperatureSensor(id: "Ta0P", name: "Ambient", component: "Ambient", celsius: 33),
            TemperatureSensor(id: "TM0P", name: "Memory", component: "Memory", celsius: 48)
        ]
        let summary = TemperatureSummary.hottestByComponent(sensors)
        XCTAssertEqual(summary.map(\.component), ["Memory", "Ambient"])
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

final class BatteryMathTests: XCTestCase {
    func testPercentFromMilliampHours() {
        XCTAssertEqual(BatteryMath.percent(current: 5040, maximum: 7200) ?? 0, 70, accuracy: 0.1)
    }

    func testPercentWhenMaxIsAlready100() {
        XCTAssertEqual(BatteryMath.percent(current: 83, maximum: 100) ?? 0, 83, accuracy: 0.1)
    }

    func testChargeState() {
        XCTAssertEqual(BatteryMath.state(isCharging: true, isPluggedIn: true, percent: 40), .charging)
        XCTAssertEqual(BatteryMath.state(isCharging: false, isPluggedIn: false, percent: 40), .discharging)
        XCTAssertEqual(BatteryMath.state(isCharging: false, isPluggedIn: true, percent: 100), .full)
        XCTAssertEqual(BatteryMath.state(isCharging: false, isPluggedIn: true, percent: 80), .pluggedNotCharging)
    }

    func testSignedWattsLabel() {
        XCTAssertEqual(BatterySnapshot.formatSignedWatts(38), "+38 W")
        XCTAssertEqual(BatterySnapshot.formatSignedWatts(-12), "−12 W")
        XCTAssertEqual(BatterySnapshot.formatSignedWatts(0), "0 W")
    }
}

final class ChassisProfileTests: XCTestCase {
    func testAirIdentifierDetection() {
        let profile = ChassisProfile(kind: .macBookAir, modelIdentifier: "Mac15,12", fanCount: 1)
        XCTAssertEqual(profile.summaryLabel, "MacBook Air · 1 fan")
        XCTAssertEqual(profile.ramp(for: .balanced).start, 68)
    }
}
