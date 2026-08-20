import Foundation
import Testing
@testable import MenuMonitorCore

@Test func metricReadingExposesOnlyAvailableValue() {
    let available: MetricReading<Int> = .available(42)
    let calibrating: MetricReading<Int> = .calibrating
    let unavailable: MetricReading<Int> = .unavailable("No sensor")

    #expect(available.value == 42)
    #expect(calibrating.value == nil)
    #expect(unavailable.value == nil)
    #expect(calibrating.statusText == "Calibrating")
    #expect(unavailable.statusText == "No sensor")
}

@Test func monotonicElapsedRejectsCounterRollback() {
    let earlier = MetricTimestamp(uptimeNanoseconds: 2_000, date: .distantPast)
    let later = MetricTimestamp(uptimeNanoseconds: 7_000, date: .distantPast)
    let rollback = MetricTimestamp(uptimeNanoseconds: 1_000, date: .distantPast)

    #expect(MetricClock.elapsedSeconds(from: earlier, to: later) == 0.000005)
    #expect(MetricClock.elapsedSeconds(from: earlier, to: rollback) == nil)
}

@Test func explicitlyDisabledIOReportNeverInventsAPowerValue() {
    let collector = PowerCollector(enableIOReport: false)
    let reading = collector.sample(at: MetricClock.now())

    guard case let .unavailable(reason) = reading else {
        Issue.record("disabled IOReport must be unavailable")
        return
    }
    #expect(reason == "IOReport disabled by request")
}

@Test func bypassPowerRequiresEveryCorroboratingSignal() {
    #expect(
        ChargingCollector.isBypassPower(
            isOnAC: true,
            externalConnected: true,
            fullyCharged: true,
            chargingCurrentMilliamps: 0,
            adapterPowerWatts: 5.4
        )
    )
    #expect(
        !ChargingCollector.isBypassPower(
            isOnAC: true,
            externalConnected: true,
            fullyCharged: false,
            chargingCurrentMilliamps: 0,
            adapterPowerWatts: 5.4
        )
    )
    #expect(
        !ChargingCollector.isBypassPower(
            isOnAC: true,
            externalConnected: true,
            fullyCharged: true,
            chargingCurrentMilliamps: 0,
            adapterPowerWatts: nil
        )
    )
}

@Test func metricFormattingUsesStableDecimalSeparator() {
    #expect(MetricFormatting.watts(4.9) == "4.9 W")
    #expect(MetricFormatting.percent(21.0) == "21%")
    #expect(MetricFormatting.decimal(3.126, maximumFractionDigits: 2) == "3.13")
    #expect(MetricFormatting.bytes(7_870_527_570) == "7.33 GB")
}
