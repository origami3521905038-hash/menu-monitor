import Foundation
import IOKit
import IOKit.ps

/// Measures only the battery's confirmed charge rate. Adapter nameplate watts are
/// retained as context and are never used as a live charging-power substitute.
public final class ChargingCollector: @unchecked Sendable {
    public init() {}

    public func sample() -> MetricReading<ChargingMetrics> {
        guard let publicState = readPublicBatteryState() else {
            return .unavailable("Internal battery state is unavailable")
        }
        guard let registry = readBatteryRegistry() else {
            return .unavailable("Battery charging telemetry is unavailable")
        }
        guard publicState.isCharging == registry.isCharging else {
            return .unavailable("Charging state sources disagree")
        }

        let ratedWatts = registry.adapterRatedWatts
        if publicState.isCharging {
            guard publicState.isOnAC,
                  let voltage = registry.chargingVoltageMillivolts,
                  let current = registry.chargingCurrentMilliamps,
                  (2_500 ... 25_000).contains(voltage),
                  (1 ... 15_000).contains(current) else {
                return .unavailable("Charging values are invalid")
            }
            let watts = Double(voltage) * Double(current) / 1_000_000
            guard watts.isFinite, watts > 0, watts <= 150 else {
                return .unavailable("Charging power is implausible")
            }
            return .available(
                ChargingMetrics(watts: watts, state: .charging, adapterRatedWatts: ratedWatts)
            )
        }

        // A battery at its charge limit commonly retains a voltage while its charging
        // current is exactly zero. That is a defensible 0 W reading, not a missing one.
        guard let current = registry.chargingCurrentMilliamps,
              current == 0,
              let voltage = registry.chargingVoltageMillivolts,
              (0 ... 25_000).contains(voltage) else {
            return .unavailable("Non-charging values are invalid")
        }
        // macOS does not expose a public "bypass" bit. Require all of the
        // corroborating registry signals before surfacing this state: AC is
        // active, the battery is externally connected and fully charged, the
        // battery charger is idle, and the adapter is still delivering power.
        // A missing or zero AdapterPower intentionally falls back to the
        // ordinary not-charging state instead of guessing.
        let state = Self.isBypassPower(
            isOnAC: publicState.isOnAC,
            externalConnected: registry.externalConnected,
            fullyCharged: registry.fullyCharged,
            chargingCurrentMilliamps: current,
            adapterPowerWatts: registry.adapterPowerWatts
        ) ? ChargingState.bypass : .notCharging
        return .available(
            ChargingMetrics(watts: 0, state: state, adapterRatedWatts: ratedWatts)
        )
    }

    /// Pure classification keeps the platform-field policy deterministic and
    /// testable without requiring a battery fixture or a privileged API.
    static func isBypassPower(
        isOnAC: Bool,
        externalConnected: Bool?,
        fullyCharged: Bool?,
        chargingCurrentMilliamps: Int64?,
        adapterPowerWatts: Double?
    ) -> Bool {
        guard isOnAC,
              externalConnected == true,
              fullyCharged == true,
              chargingCurrentMilliamps == 0,
              let adapterPowerWatts,
              adapterPowerWatts.isFinite,
              (0.1 ... 500).contains(adapterPowerWatts) else {
            return false
        }
        return true
    }

    private struct PublicBatteryState {
        let isCharging: Bool
        let isOnAC: Bool
    }

    private struct RegistryBatteryState {
        let isCharging: Bool
        let externalConnected: Bool?
        let fullyCharged: Bool?
        let chargingVoltageMillivolts: Int64?
        let chargingCurrentMilliamps: Int64?
        let adapterRatedWatts: Double?
        let adapterPowerWatts: Double?
    }

    private func readPublicBatteryState() -> PublicBatteryState? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as NSArray
        for item in sources {
            guard let description = IOPSGetPowerSourceDescription(info, item as CFTypeRef)?
                .takeUnretainedValue() as? [String: Any],
                description["Type"] as? String == "InternalBattery",
                let isCharging = boolValue(description["Is Charging"]),
                let sourceState = description["Power Source State"] as? String else {
                continue
            }
            return PublicBatteryState(isCharging: isCharging, isOnAC: sourceState == "AC Power")
        }
        return nil
    }

    private func readBatteryRegistry() -> RegistryBatteryState? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let isCharging = boolValue(property(named: "IsCharging", service: service)),
              let chargerData = property(named: "ChargerData", service: service) as? [String: Any] else {
            return nil
        }
        let voltage = integerValue(chargerData["ChargingVoltage"])
        let current = integerValue(chargerData["ChargingCurrent"])
        let externalConnected = boolValue(property(named: "ExternalConnected", service: service))
        let fullyCharged = boolValue(property(named: "FullyCharged", service: service))
        let batteryData = property(named: "BatteryData", service: service) as? [String: Any]
        let adapterPower = realValue(batteryData?["AdapterPower"])
        let adapterDetails = property(named: "AdapterDetails", service: service) as? [String: Any]
        let ratedWatts: Double?
        if let watts = integerValue(adapterDetails?["Watts"]), watts > 0, watts <= 500 {
            ratedWatts = Double(watts)
        } else {
            ratedWatts = nil
        }
        return RegistryBatteryState(
            isCharging: isCharging,
            externalConnected: externalConnected,
            fullyCharged: fullyCharged,
            chargingVoltageMillivolts: voltage,
            chargingCurrentMilliamps: current,
            adapterRatedWatts: ratedWatts,
            adapterPowerWatts: adapterPower
        )
    }

    private func property(named name: String, service: io_registry_entry_t) -> Any? {
        let key = name as NSString
        return IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        guard let value = value as? NSNumber else { return nil }
        let raw = value.int64Value
        guard raw == 0 || raw == 1 else { return nil }
        return raw == 1
    }

    private func integerValue(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber else { return nil }
        return number.int64Value
    }

    private func realValue(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }
}
