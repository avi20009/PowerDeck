import Foundation

struct MacIdentity {
    var computerName: String
    var modelIdentifier: String
    var modelName: String
    var chip: String
    var memoryBytes: UInt64

    var isMacBookAir: Bool { modelName.hasPrefix("MacBook Air") }
}

/// One fixed voltage/current level a USB-C PD charger offers.
struct PDProfile: Identifiable, Hashable {
    var index: Int
    var volts: Double
    var amps: Double

    var watts: Double { volts * amps }
    var id: Int { index }
}

struct ChargerInfo {
    var ratedWatts: Double
    var contractVolts: Double
    var contractAmps: Double
    var kind: String
    var isWireless: Bool
    var profiles: [PDProfile]
    var activeProfileIndex: Int?
    var brand: String?
    var model: String?
    var portID: String?

    var displayName: String {
        switch (brand, model) {
        case let (brand?, model?): return "\(brand) \(model)"
        case let (brand?, nil): return "\(brand) \(Int(ratedWatts)) W charger"
        case let (nil, model?): return model
        default: return "\(Int(ratedWatts)) W \(kind)"
        }
    }

    /// "Lenovo 45 W charger", for use inside sentences.
    var shortName: String {
        "\(brand.map { "\($0) " } ?? "")\(Int(ratedWatts)) W charger"
    }
}

struct BatteryInfo {
    var percent: Int
    var isCharging: Bool
    var isFullyCharged: Bool
    var volts: Double
    /// Positive while charging, negative while draining.
    var amps: Double
    var cycleCount: Int
    var designCycleCount: Int
    var designCapacity: Int
    var maxCapacity: Int
    var minutesRemaining: Int?
    var slowChargingReason: Int
    var notChargingReason: Int
    var thermallyLimited: Bool

    var watts: Double { volts * amps }
    var isDischarging: Bool { amps < -0.05 }
    var healthPercent: Double {
        designCapacity > 0 ? min(100, Double(maxCapacity) / Double(designCapacity) * 100) : 0
    }
}

/// Live power measurements from the Mac's power controller.
struct PowerTelemetry {
    var inputWatts: Double
    var inputVolts: Double
    var inputAmps: Double
    /// Everything downstream of the charger except the battery, including USB accessories.
    var systemWatts: Double
    var conversionLossWatts: Double
}

/// What a port is currently sourcing to whatever is plugged into it.
struct PortPowerOut {
    var portIndex: Int
    var watts: Double
    var volts: Double
    var amps: Double
    var budgetVolts: Double
    var budgetAmps: Double

    var budgetWatts: Double { budgetVolts * budgetAmps }
}

enum PortRole {
    case chargingMac, poweringDevice, data, attached, empty

    var label: String {
        switch self {
        case .chargingMac: "Charging Mac"
        case .poweringDevice: "Powering device"
        case .data: "Data"
        case .attached: "Attached"
        case .empty: "Empty"
        }
    }
}

struct PortInfo: Identifiable {
    let id: String
    var kind: String
    var number: Int
    var isConnected: Bool
    var activeTransports: [String]
    var supportedTransports: [String]
    var partnerName: String?
    var partnerBrand: String?
    var overcurrentCount: Int
    var isChargingMac: Bool
    var powerOut: PortPowerOut?
    var devices: [USBDevice] = []

    var isMagSafe: Bool { kind.hasPrefix("MagSafe") }
    var title: String { isMagSafe ? kind : "\(kind) · Port \(number)" }
    var shortTitle: String { isMagSafe ? kind : "\(kind) \(number)" }
    var hasData: Bool { activeTransports.contains { $0.hasPrefix("USB") || $0 == "CIO" } }

    var role: PortRole {
        if isChargingMac { return .chargingMac }
        if let powerOut, powerOut.watts >= 0.05 { return .poweringDevice }
        if hasData || !devices.isEmpty { return .data }
        if isConnected { return .attached }
        return .empty
    }

    var capabilities: [String] {
        if isMagSafe { return ["Charging only", "Fastest way to charge"] }
        var caps: [String] = []
        if supportedTransports.contains("CIO") {
            caps.append("Thunderbolt / USB4 · 40 Gb/s")
        } else if supportedTransports.contains("USB3") {
            caps.append("USB 3 · 10 Gb/s")
        } else if supportedTransports.contains("USB2") {
            caps.append("USB 2 · 480 Mb/s")
        }
        if supportedTransports.contains("DisplayPort") { caps.append("Video out") }
        caps.append("15 W power out")
        return caps
    }
}

enum DeviceKind: Hashable {
    case iPhone, iPad, watch, phone, wearable, charger, storage, hub, keyboard, mouse, audio, camera, display, gameController, other

    var label: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .watch: "Apple Watch"
        case .phone: "Phone"
        case .wearable: "Wearable"
        case .charger: "Charging accessory"
        case .storage: "Storage"
        case .hub: "USB hub"
        case .keyboard: "Keyboard"
        case .mouse: "Mouse / pointer"
        case .audio: "Audio device"
        case .camera: "Camera"
        case .display: "Display"
        case .gameController: "Game controller"
        case .other: "USB accessory"
        }
    }

    var symbol: String {
        switch self {
        case .iPhone: "iphone"
        case .iPad: "ipad"
        case .watch: "applewatch"
        case .phone: "smartphone"
        case .wearable: "heart.circle"
        case .charger: "battery.100percent.bolt"
        case .storage: "externaldrive.fill"
        case .hub: "point.3.filled.connected.trianglepath.dotted"
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .audio: "headphones"
        case .camera: "web.camera"
        case .display: "display"
        case .gameController: "gamecontroller"
        case .other: "cable.connector"
        }
    }

    var isPhoneLike: Bool { self == .iPhone || self == .iPad || self == .phone }
}

struct USBDevice: Identifiable, Hashable {
    let id: String
    var name: String
    var vendor: String
    var vendorID: Int
    var productID: Int
    /// Negotiated link speed in bits per second.
    var linkSpeed: Int
    /// Matches `PortInfo.id`, e.g. "Port-USB-C@1".
    var portID: String?
    var kind: DeviceKind

    var speedLabel: String { Fmt.linkSpeed(linkSpeed) }

    var generation: String {
        switch linkSpeed {
        case 0: "Unknown"
        case ...1_500_000: "USB 1.0 Low Speed"
        case ...12_000_000: "USB 1.1 Full Speed"
        case ...480_000_000: "USB 2.0 High Speed"
        case ...5_000_000_000: "USB 3 (5 Gb/s)"
        case ...10_000_000_000: "USB 3.2 Gen 2"
        case ...20_000_000_000: "USB 3.2 Gen 2×2"
        default: "USB4 / Thunderbolt"
        }
    }
}

enum MemoryPressure {
    case normal, warning, critical

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }
}

struct SystemStats {
    var cpuUsage: Double
    var coreUsage: [Double]
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var swapUsed: UInt64
    var memoryPressure: MemoryPressure
    var thermalState: ProcessInfo.ThermalState
    var lowPowerMode: Bool
}

struct ProcessUsage: Identifiable {
    let id: Int32
    let name: String
    /// Percent of one core, so a busy multi-threaded app can exceed 100.
    let cpuPercent: Double
    /// A regular app the user can quit, as opposed to a background process.
    let isApp: Bool
}

enum Severity: Int, Comparable {
    case good, info, tip, warning, critical

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct Insight: Identifiable {
    let severity: Severity
    let title: String
    let detail: String

    var id: String { title }
    /// The title without its live numbers, so "CPU is maxed out (91%)" stays the same insight as it changes.
    var key: String { title.filter { !$0.isNumber && $0 != "." } }

    init(_ severity: Severity, _ title: String, _ detail: String) {
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

/// One line of a device's capability verdict.
struct CapabilityLine: Identifiable {
    let tone: Severity
    let text: String

    var id: String { text }

    init(_ tone: Severity, _ text: String) {
        self.tone = tone
        self.text = text
    }
}

struct Snapshot {
    var date: Date
    var mac: MacIdentity
    var charger: ChargerInfo?
    var battery: BatteryInfo?
    var telemetry: PowerTelemetry?
    var ports: [PortInfo]
    var devices: [USBDevice]
    var system: SystemStats
    var topProcesses: [ProcessUsage]
    /// When the current charger was plugged in (or when PowerDeck started, if it already was).
    var chargerConnectedSince: Date? = nil

    /// A charger is attached but no power is flowing yet. macOS takes up to a minute to start
    /// drawing from a freshly plugged-in charger, and longer if the charger itself has no power.
    var chargerIdle: Bool {
        charger != nil && (telemetry?.inputWatts ?? 0) < 0.5
    }

    /// Just switched to battery: macOS zeroes its power readings for a while and re-measures.
    var isMeasuring: Bool {
        guard charger == nil, let battery else { return false }
        return (telemetry?.systemWatts ?? 0) < 0.3 && abs(battery.amps) < 0.1
    }

    var accessoryWatts: Double {
        ports.compactMap(\.powerOut?.watts).reduce(0, +)
    }

    /// Power used by the Mac itself, excluding what it passes on to accessories.
    var macWatts: Double {
        let system = telemetry.map(\.systemWatts).flatMap { $0 > 0 ? $0 : nil } ?? max(0, -(battery?.watts ?? 0))
        return max(0, system - accessoryWatts)
    }

    /// Power leaving the battery. On battery the Mac's load reading is used: the battery's own current
    /// only updates every ~20 seconds, and the load keeps "in = out" adding up for the user.
    var batteryDrawWatts: Double {
        guard let battery else { return 0 }
        if charger == nil || chargerIdle, let system = telemetry?.systemWatts, system > 0 { return system }
        return max(0, -battery.watts)
    }

    /// Wh left in the battery at its current charge.
    var batteryEnergyLeftWh: Double {
        guard let battery else { return 0 }
        return Double(battery.maxCapacity) * Double(battery.percent) / 100 * battery.volts / 1000
    }

    func port(for device: USBDevice) -> PortInfo? {
        ports.first { $0.id == device.portID }
    }

    /// Power out to a device, when it is the only thing on its port.
    func powerOut(for device: USBDevice) -> PortPowerOut? {
        guard let port = port(for: device), port.devices.count == 1 else { return nil }
        return port.powerOut
    }
}

struct PowerSample: Identifiable {
    let date: Date
    let input: Double
    let mac: Double
    let battery: Double
    let accessories: Double
    let cpu: Double
    let memory: Double

    var id: Date { date }
}

/// Something that happened while PowerDeck was watching: a plug-in, an unplug, a new warning.
struct ActivityEvent: Identifiable {
    enum Kind { case connected, disconnected, power, warning, info }

    let id = UUID()
    let date: Date
    let kind: Kind
    let title: String
    let detail: String
    let symbol: String
}

/// Energy totals since the app started, integrated from each sample.
struct SessionStats {
    var start: Date
    var fromChargerWh: Double = 0
    var intoBatteryWh: Double = 0
    var fromBatteryWh: Double = 0
    var toDevicesWh: Double = 0
    var perDeviceWh: [String: Double] = [:]
    var peakMacWatts: Double = 0
}
