import Foundation

enum Fmt {
    static func number(_ value: Double) -> String {
        abs(value) >= 10 ? String(format: "%.1f", value) : String(format: "%.2f", value)
    }

    static func watts(_ value: Double) -> String { "\(number(value)) W" }

    static func wattHours(_ value: Double) -> String {
        value >= 10 ? String(format: "%.1f Wh", value) : String(format: "%.2f Wh", value)
    }

    static func signedWatts(_ value: Double) -> String {
        value >= 0 ? "+\(watts(value))" : "−\(watts(-value))"
    }

    static func volts(_ value: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f V", value)
    }

    static func amps(_ value: Double) -> String {
        abs(value) < 1 ? "\(Int((value * 1000).rounded())) mA" : String(format: "%.2f A", value)
    }

    static func signedAmps(_ value: Double) -> String {
        value >= 0 ? "+\(amps(value))" : "−\(amps(-value))"
    }

    /// "20 V", "5 V" — for USB PD levels, which are whole or simple numbers.
    static func roundVolts(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) V" : String(format: "%g V", value)
    }

    static func roundAmps(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) A" : String(format: "%g A", value)
    }

    /// Uses non-breaking spaces so "1 h 13 min" never wraps mid-way.
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60, mins = minutes % 60
        return hours > 0 ? "\(hours)\u{00A0}h\u{00A0}\(mins)\u{00A0}min" : "\(mins)\u{00A0}min"
    }

    static func gigabytes(_ bytes: UInt64, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f GB", Double(bytes) / 1_073_741_824)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func linkSpeed(_ bitsPerSecond: Int) -> String {
        switch bitsPerSecond {
        case 0:
            return "—"
        case ..<1_000_000_000:
            let mbps = Double(bitsPerSecond) / 1_000_000
            return mbps == mbps.rounded() ? "\(Int(mbps)) Mb/s" : String(format: "%.1f Mb/s", mbps)
        default:
            let gbps = Double(bitsPerSecond) / 1_000_000_000
            return gbps == gbps.rounded() ? "\(Int(gbps)) Gb/s" : String(format: "%.1f Gb/s", gbps)
        }
    }

    static func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case 88...: "battery.100percent"
        case 63...: "battery.75percent"
        case 38...: "battery.50percent"
        case 13...: "battery.25percent"
        default: "battery.0percent"
        }
    }
}
