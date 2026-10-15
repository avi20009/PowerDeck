import SwiftUI

struct BatteryCard: View {
    let battery: BatteryInfo?

    var body: some View {
        Card("Battery", symbol: "battery.100percent",
             help: "Health compares what the battery holds today with what it held new. Apple considers below 80% worn.") {
            if let b = battery {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 20) {
                        RingGauge(fraction: Double(b.percent) / 100, color: Theme.battery,
                                  value: "\(b.percent)%", caption: state(b))
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                KeyValueRow(key: "Health", value: "\(Int(b.healthPercent.rounded()))%")
                                MeterBar(fraction: b.healthPercent / 100,
                                         color: b.healthPercent >= 80 ? Theme.good : Theme.warning)
                            }
                            KeyValueRow(key: "Charge cycles", value: "\(b.cycleCount) of \(b.designCycleCount)")
                            KeyValueRow(key: "Holds", value: "\(b.maxCapacity.formatted()) of \(b.designCapacity.formatted()) mAh")
                            KeyValueRow(key: b.isDischarging ? "Time left" : "Full in",
                                        value: b.minutesRemaining.map { Fmt.duration(minutes: $0) } ?? "–")
                        }
                    }
                    HStack(spacing: 10) {
                        MetricBox(label: "Voltage", value: Fmt.volts(b.volts), detail: "battery pack")
                        MetricBox(label: "Current", value: Fmt.signedAmps(b.amps),
                                  detail: b.amps >= 0 ? "into battery" : "out of battery")
                        MetricBox(label: "Power", value: Fmt.signedWatts(b.watts),
                                  detail: b.watts >= 0 ? "charging" : "draining")
                    }
                }
            } else {
                EmptyState(symbol: "powerplug.fill", title: "No battery",
                           detail: "This Mac runs straight from wall power.")
            }
        }
    }

    private func state(_ b: BatteryInfo) -> String {
        if b.isCharging && b.watts > 0.05 { return "charging" }
        if b.isDischarging { return "on battery" }
        return b.percent >= 100 || b.isFullyCharged ? "full" : "on hold"
    }
}

struct ChargerCard: View {
    let charger: ChargerInfo?
    let telemetry: PowerTelemetry?
    let ports: [PortInfo]
    let mac: MacIdentity

    var body: some View {
        Card("Power adapter", symbol: "powerplug",
             help: "USB-C chargers offer several voltage levels; your Mac picks the best one. The ticked level is in use.",
             trailing: {
                 if let charger {
                     let verdict = verdict(for: charger)
                     Pill(text: verdict.text, color: verdict.color, symbol: verdict.symbol)
                 }
             }) {
            if let charger {
                let portName = ports.first { $0.id == charger.portID }?.shortTitle
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(charger.displayName).font(.system(size: 17, weight: .semibold))
                        Text("\(Int(charger.ratedWatts)) W \(charger.kind)\(portName.map { " · on \($0)" } ?? "")")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    VStack(spacing: 8) {
                        if let t = telemetry {
                            KeyValueRow(key: "Delivering now",
                                        value: "\(Fmt.watts(t.inputWatts))  (\(Fmt.volts(t.inputVolts)) × \(Fmt.amps(t.inputAmps)))")
                            KeyValueRow(key: "Headroom left", value: Fmt.watts(max(0, charger.ratedWatts - t.inputWatts)))
                            KeyValueRow(key: "Lost as heat", value: Fmt.watts(t.conversionLossWatts))
                        }
                        KeyValueRow(key: "Agreed contract",
                                    value: "\(Fmt.roundVolts(charger.contractVolts)) × \(Fmt.roundAmps(charger.contractAmps))")
                    }
                    if !charger.profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SmallLabel("Voltages it offers")
                            profileGrid(charger)
                        }
                    }
                    Text(verdict(for: charger).advice)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                EmptyState(symbol: "battery.75percent", title: "Running on battery",
                           detail: "Plug in a charger to see its wattage, the voltage your Mac agreed on, every power level it supports, and whether it's strong enough for this Mac.")
            }
        }
    }

    /// Rates the charger against this Mac. MacBook Air fast-charges from 70 W; Pros want more.
    private func verdict(for charger: ChargerInfo) -> (text: String, color: Color, symbol: String, advice: String) {
        let recommended = mac.isMacBookAir ? 30.0 : 70.0
        let fast = mac.isMacBookAir ? 70.0 : 96.0
        if charger.ratedWatts >= fast {
            return ("Fast charging", Theme.good, "hare.fill",
                    "This charger is strong enough for the fastest charging this Mac supports.")
        }
        if charger.ratedWatts >= recommended {
            return ("Good for everyday", Theme.good, "checkmark.circle.fill",
                    "Plenty for everyday use. For the fastest charging, use a \(Int(fast)) W or stronger USB-C charger.")
        }
        return ("Underpowered", Theme.warning, "exclamationmark.triangle.fill",
                "This charger is below the \(Int(recommended)) W this Mac needs, so it may charge slowly or not at all under heavy use.")
    }

    private func profileGrid(_ charger: ChargerInfo) -> some View {
        let profiles = charger.profiles
        let rows = stride(from: 0, to: profiles.count, by: 2).map { Array(profiles[$0..<min($0 + 2, profiles.count)]) }
        return VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    ForEach(rows[index]) { profile in
                        let active = profile.index == charger.activeProfileIndex
                        HStack(spacing: 6) {
                            if active {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.powerIn)
                            }
                            Text("\(Fmt.roundVolts(profile.volts)) · \(Fmt.roundAmps(profile.amps))")
                                .font(.system(size: 12, weight: .medium))
                            Spacer(minLength: 4)
                            Text("\(Int(profile.watts.rounded())) W")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(active ? Theme.powerIn.opacity(0.12) : Theme.raised,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(active ? Theme.powerIn.opacity(0.45) : Color.clear)
                        )
                    }
                    if rows[index].count == 1 {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }
}
