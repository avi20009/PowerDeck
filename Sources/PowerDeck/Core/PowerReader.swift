import Foundation

struct PowerReading {
    var charger: ChargerInfo?
    var battery: BatteryInfo?
    var telemetry: PowerTelemetry?
    var portOutputs: [PortPowerOut]
}

/// Reads the AppleSmartBattery service: battery, charger, live power telemetry and per-port power out.
enum PowerReader {
    static func read() -> PowerReading {
        guard let props = IORegistry.allProperties("AppleSmartBattery").first else {
            return PowerReading(charger: nil, battery: nil, telemetry: nil, portOutputs: [])
        }
        let onExternalPower = props.bool("ExternalConnected") ?? false
        return PowerReading(
            charger: onExternalPower ? charger(props) : nil,
            battery: battery(props),
            telemetry: telemetry(props),
            portOutputs: props.dicts("PowerOutDetails").compactMap(portOutput)
        )
    }

    /// Registry values are milli-units (mV, mA, mW).
    private static func milli(_ value: Int?) -> Double { Double(value ?? 0) / 1000 }

    private static func charger(_ props: [String: Any]) -> ChargerInfo? {
        guard let adapter = props.dict("AdapterDetails") else { return nil }
        let profiles = adapter.dicts("UsbHvcMenu").enumerated().map { offset, entry in
            PDProfile(index: entry.int("Index") ?? offset,
                      volts: milli(entry.int("MaxVoltage")),
                      amps: milli(entry.int("MaxCurrent")))
        }
        let isWireless = adapter.bool("IsWireless") ?? false
        return ChargerInfo(
            ratedWatts: adapter.double("Watts") ?? 0,
            contractVolts: milli(adapter.int("AdapterVoltage")),
            contractAmps: milli(adapter.int("Current")),
            kind: friendlyKind(adapter.string("Description"), wireless: isWireless),
            isWireless: isWireless,
            profiles: profiles,
            activeProfileIndex: adapter.int("UsbHvcHvcIndex"),
            brand: nil,
            model: nil,
            portID: nil
        )
    }

    private static func friendlyKind(_ description: String?, wireless: Bool) -> String {
        if wireless { return "wireless charger" }
        switch description?.lowercased() {
        case "pd charger": return "USB-C PD charger"
        case nil: return "power adapter"
        case let other?: return other
        }
    }

    private static func battery(_ props: [String: Any]) -> BatteryInfo? {
        guard props.bool("BatteryInstalled") ?? true else { return nil }
        let data = props.dict("BatteryData") ?? [:]
        func value(_ key: String) -> Int? { props.int(key) ?? data.int(key) }

        // On Apple silicon CurrentCapacity is already a percentage (MaxCapacity is 100);
        // on Intel both are mAh, so the ratio works for either.
        let current = value("CurrentCapacity") ?? 0
        let maxValue = props.int("MaxCapacity") ?? 100
        let chargerData = props.dict("ChargerData") ?? [:]
        let remaining = props.int("TimeRemaining") ?? 0

        return BatteryInfo(
            percent: maxValue > 0 ? min(100, current * 100 / maxValue) : current,
            isCharging: props.bool("IsCharging") ?? false,
            isFullyCharged: props.bool("FullyCharged") ?? false,
            volts: milli(props.int("Voltage")),
            amps: milli(props.int("InstantAmperage") ?? props.int("Amperage")),
            cycleCount: value("CycleCount") ?? 0,
            designCycleCount: props.int("DesignCycleCount9C") ?? 1000,
            designCapacity: value("DesignCapacity") ?? 0,
            maxCapacity: value("NominalChargeCapacity") ?? value("AppleRawMaxCapacity") ?? 0,
            // 65535 means "calculating"; right after a power change macOS can also report absurd values.
            minutesRemaining: (1..<(48 * 60)).contains(remaining) ? remaining : nil,
            slowChargingReason: chargerData.int("SlowChargingReason") ?? 0,
            notChargingReason: chargerData.int("NotChargingReason") ?? 0,
            thermallyLimited: (chargerData.int("TimeChargingThermallyLimited") ?? 0) > 0
        )
    }

    private static func telemetry(_ props: [String: Any]) -> PowerTelemetry? {
        guard let t = props.dict("PowerTelemetryData") else { return nil }
        return PowerTelemetry(
            inputWatts: max(0, milli(t.int("SystemPowerIn"))),
            inputVolts: milli(t.int("SystemVoltageIn")),
            inputAmps: milli(t.int("SystemCurrentIn")),
            systemWatts: milli(t.int("SystemLoad")),
            conversionLossWatts: milli(t.int("AdapterEfficiencyLoss"))
        )
    }

    private static func portOutput(_ entry: [String: Any]) -> PortPowerOut? {
        guard let index = entry.int("PortIndex") else { return nil }
        return PortPowerOut(
            portIndex: index,
            watts: milli(entry.int("Watts")),
            volts: milli(entry.int("AdapterVoltage")),
            amps: milli(entry.int("Current")),
            budgetVolts: milli(entry.int("ConfiguredVoltage") ?? 5000),
            budgetAmps: milli(entry.int("ConfiguredCurrent"))
        )
    }
}
