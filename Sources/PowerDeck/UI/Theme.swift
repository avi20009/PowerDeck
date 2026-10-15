import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0A0C10)
    static let card = Color(hex: 0x12151B)
    static let cardHover = Color(hex: 0x161A21)
    static let raised = Color(hex: 0x1A1E26)
    static let border = Color.white.opacity(0.07)

    static let textPrimary = Color(hex: 0xE8ECF2)
    static let textSecondary = Color(hex: 0x8B93A1)
    static let textTertiary = Color(hex: 0x5D6573)

    // One color per power flow, used everywhere that flow appears.
    static let powerIn = Color(hex: 0x34D399)
    static let mac = Color(hex: 0x60A5FA)
    static let battery = Color(hex: 0xFBBF24)
    static let accessory = Color(hex: 0xC084FC)
    static let loss = Color(hex: 0x6B7280)
    static let memory = Color(hex: 0x22D3EE)

    static let good = powerIn
    static let info = mac
    static let tip = Color(hex: 0x22D3EE)
    static let warning = Color(hex: 0xF59E0B)
    static let critical = Color(hex: 0xF87171)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension Severity {
    var color: Color {
        switch self {
        case .good: Theme.good
        case .info: Theme.info
        case .tip: Theme.tip
        case .warning: Theme.warning
        case .critical: Theme.critical
        }
    }

    var symbol: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .tip: "lightbulb.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

extension PortRole {
    var color: Color {
        switch self {
        case .chargingMac: Theme.powerIn
        case .poweringDevice: Theme.accessory
        case .data: Theme.mac
        case .attached: Theme.textSecondary
        case .empty: Theme.textTertiary
        }
    }
}

extension DeviceKind {
    var color: Color {
        switch self {
        case .iPhone, .iPad, .phone, .watch: Theme.mac
        case .charger, .wearable: Theme.powerIn
        case .storage: Theme.battery
        case .keyboard, .mouse, .gameController: Theme.accessory
        case .audio: Color(hex: 0xF472B6)
        case .camera, .display: Theme.tip
        case .hub, .other: Theme.textSecondary
        }
    }
}

extension MemoryPressure {
    var color: Color {
        switch self {
        case .normal: Theme.memory
        case .warning: Theme.warning
        case .critical: Theme.critical
        }
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "Cool"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Overheating"
        @unknown default: "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .nominal: Theme.good
        case .fair: Theme.battery
        case .serious: Theme.warning
        case .critical: Theme.critical
        @unknown default: Theme.textSecondary
        }
    }
}

extension ActivityEvent.Kind {
    var color: Color {
        switch self {
        case .connected: Theme.powerIn
        case .disconnected: Theme.textSecondary
        case .power: Theme.battery
        case .warning: Theme.warning
        case .info: Theme.info
        }
    }
}

extension EnvironmentValues {
    /// True when the view is being rendered to an image, so entrance animations start finished.
    @Entry var staticRender = false
}

/// The one-line power status shown in the header and the menu bar.
enum PowerStatus {
    static func describe(_ s: Snapshot) -> (text: String, color: Color, symbol: String) {
        guard let battery = s.battery else { return ("On wall power", Theme.powerIn, "powerplug.fill") }
        guard let charger = s.charger else {
            return ("On battery · \(battery.percent)%", Theme.battery, Fmt.batterySymbol(battery.percent))
        }
        if s.chargerIdle { return ("Charger starting up", Theme.battery, "hourglass") }
        if battery.isDischarging { return ("Plugged in · still draining", Theme.critical, "exclamationmark.triangle.fill") }
        if battery.isCharging && battery.watts > 0.05 { return ("Charging · \(Int(charger.ratedWatts)) W", Theme.powerIn, "bolt.fill") }
        if battery.isFullyCharged || battery.percent >= 100 { return ("Fully charged", Theme.powerIn, "battery.100percent.bolt") }
        return ("Plugged in · charging on hold", Theme.battery, "pause.circle.fill")
    }
}
