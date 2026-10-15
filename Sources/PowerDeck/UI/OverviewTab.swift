import SwiftUI

/// The simple home screen: status in plain words, the live flow, and what needs attention.
struct OverviewTab: View {
    let monitor: Monitor
    let snapshot: Snapshot
    let openTab: (DashboardTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                HeroCard(snapshot: snapshot, insights: monitor.insights)
                    .frame(width: 390)
                    .appear(0)
                Card("Live power flow", symbol: "point.3.filled.connected.trianglepath.dotted",
                     help: "Where your power comes from and where it goes, live. The faster the dots move, the more watts are flowing.") {
                    FlowDiagram(snapshot: snapshot)
                        .frame(height: 280)
                }
                .appear(1)
            }
            .fixedSize(horizontal: false, vertical: true)

            OverviewTiles(snapshot: snapshot, history: monitor.history)
                .appear(2)

            HStack(alignment: .top, spacing: 16) {
                InsightsCard(insights: monitor.insights, limit: 4)
                    .appear(3)
                VStack(spacing: 16) {
                    PluggedInCard(snapshot: snapshot) { openTab(.devices) }
                    ActivityCard(events: monitor.events, limit: 4)
                }
                .frame(width: 470)
                .appear(4)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Turns the snapshot into the one-glance summary at the top of the Overview.
private struct Summary {
    var headline: String
    var subline: String
    var verdict: String
    var verdictColor: Color
    var verdictSymbol: String

    init(snapshot: Snapshot, insights: [Insight]) {
        if let battery = snapshot.battery {
            if snapshot.charger != nil {
                if snapshot.chargerIdle {
                    headline = "Charger connected, starting up"
                    subline = "Running on battery until power starts flowing."
                } else if battery.isDischarging {
                    headline = "Plugged in, but still draining"
                    subline = "Your charger can't keep up with what your Mac needs."
                } else if battery.isCharging && battery.watts > 0.05 {
                    headline = battery.minutesRemaining.map { "Charging, full in \(Fmt.duration(minutes: $0))" } ?? "Charging"
                    subline = "Adding \(Fmt.watts(battery.watts)) to the battery right now."
                } else if battery.isFullyCharged || battery.percent >= 100 {
                    headline = "Fully charged"
                    subline = "Your Mac is running straight from the charger."
                } else {
                    headline = "Plugged in, charging paused"
                    subline = "macOS is holding the charge to protect the battery."
                }
            } else {
                headline = battery.minutesRemaining.map { "On battery, \(Fmt.duration(minutes: $0)) left" } ?? "On battery"
                if snapshot.isMeasuring {
                    subline = "Just switched to battery. Measuring power use…"
                } else if snapshot.accessoryWatts > 0.5 {
                    subline = "Using \(Fmt.watts(snapshot.batteryDrawWatts)): \(Fmt.watts(snapshot.macWatts)) for your Mac and \(Fmt.watts(snapshot.accessoryWatts)) for plugged-in devices."
                } else {
                    subline = "Your Mac is using \(Fmt.watts(snapshot.batteryDrawWatts)) right now."
                }
            }
        } else {
            headline = "On wall power"
            subline = "Your Mac is using \(Fmt.watts(snapshot.macWatts))."
        }

        let problems = insights.filter { $0.severity >= .warning }.count
        let tips = insights.filter { $0.severity == .tip }.count
        if problems > 0 {
            verdict = "\(problems) thing\(problems == 1 ? "" : "s") to check"
            verdictColor = Theme.warning
            verdictSymbol = "exclamationmark.triangle.fill"
        } else if tips > 0 {
            verdict = "All good · \(tips) tip\(tips == 1 ? "" : "s")"
            verdictColor = Theme.tip
            verdictSymbol = "lightbulb.fill"
        } else {
            verdict = "Everything looks good"
            verdictColor = Theme.good
            verdictSymbol = "checkmark.circle.fill"
        }
    }
}

struct HeroCard: View {
    let snapshot: Snapshot
    let insights: [Insight]

    @Environment(\.staticRender) private var staticRender

    var body: some View {
        let summary = Summary(snapshot: snapshot, insights: insights)
        let battery = snapshot.battery
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                ZStack(alignment: .topTrailing) {
                    RingGauge(fraction: Double(battery?.percent ?? 100) / 100, color: Theme.battery,
                              value: battery.map { "\($0.percent)%" } ?? "AC",
                              caption: "battery", size: 128, lineWidth: 11)
                    if let battery, battery.isCharging, battery.watts > 0.05 {
                        ZStack {
                            if !staticRender {
                                PulseRing(color: Theme.battery, size: 26, scale: 1.9, duration: 1.6)
                                    .frame(width: 26, height: 26)
                            }
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.8))
                                .frame(width: 26, height: 26)
                                .background(Theme.battery, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.card, lineWidth: 3))
                        }
                        .offset(x: 2, y: -2)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary.headline)
                        .font(.system(size: 20, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.interpolate)
                        .animation(.smooth, value: summary.headline)
                    Text(summary.subline)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Pill(text: summary.verdict, color: summary.verdictColor, symbol: summary.verdictSymbol)
                        .padding(.top, 2)
                }
            }
            Divider().overlay(Theme.border)
            VStack(spacing: 11) {
                KeyValueRow(key: "Battery health", value: battery.map { "\(Int($0.healthPercent.rounded()))% · \($0.cycleCount) cycles" } ?? "–")
                KeyValueRow(key: "Charger", value: snapshot.charger?.shortName ?? "Not plugged in")
                KeyValueRow(key: "Devices", value: devicesText)
                KeyValueRow(key: "Temperature", value: snapshot.system.thermalState.label)
            }
        }
        .cardStyle(padding: 20)
    }

    private var devicesText: String {
        let count = snapshot.devices.count
        return count == 0 ? "None plugged in" : "\(count) connected"
    }
}

struct OverviewTiles: View {
    let snapshot: Snapshot
    let history: [PowerSample]

    var body: some View {
        let system = snapshot.system
        HStack(spacing: 14) {
            sourceTile
            StatTile(title: "Your Mac", symbol: "laptopcomputer",
                     value: Fmt.number(snapshot.macWatts), unit: "W",
                     detail: "Running \(system.thermalState.label.lowercased())",
                     color: Theme.mac, spark: history.map(\.mac),
                     help: "Power the Mac itself is using right now, not counting the battery or plugged-in devices.")
            StatTile(title: "Devices", symbol: "cable.connector",
                     value: Fmt.number(snapshot.accessoryWatts), unit: "W",
                     detail: snapshot.devices.isEmpty ? "Nothing plugged in" : "\(snapshot.devices.count) USB device\(snapshot.devices.count == 1 ? "" : "s")",
                     color: Theme.accessory, spark: history.map(\.accessories),
                     help: "Power your Mac's ports are sending out to phones and accessories.")
            StatTile(title: "CPU", symbol: "cpu",
                     value: "\(Int((system.cpuUsage * 100).rounded()))", unit: "%",
                     detail: snapshot.topProcesses.first.map { "Busiest: \($0.name)" } ?? "Mostly idle",
                     color: Theme.tip, spark: history.map { $0.cpu * 100 }, sparkCeiling: 100,
                     help: "How busy the processor is across all cores.")
            StatTile(title: "Memory", symbol: "memorychip",
                     value: String(format: "%.1f", Double(system.memoryUsed) / 1_073_741_824), unit: "GB",
                     detail: "of \(Fmt.gigabytes(system.memoryTotal, decimals: 0)) · \(system.memoryPressure.label.lowercased())",
                     color: system.memoryPressure.color,
                     progress: Double(system.memoryUsed) / Double(max(system.memoryTotal, 1)),
                     help: "Memory in use. A high number is normal; pressure tells you if it's actually a problem.")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var sourceTile: some View {
        if let charger = snapshot.charger, let t = snapshot.telemetry {
            StatTile(title: "Power in", symbol: "bolt.fill",
                     value: Fmt.number(t.inputWatts), unit: "W",
                     detail: "\(Fmt.volts(t.inputVolts, decimals: 1)) × \(Fmt.amps(t.inputAmps)) · \(Int(charger.ratedWatts)) W max",
                     color: Theme.powerIn, spark: history.map(\.input),
                     help: "What your charger is delivering right now, measured by the Mac.")
        } else if let battery = snapshot.battery {
            StatTile(title: "Battery draw", symbol: Fmt.batterySymbol(battery.percent),
                     value: Fmt.number(snapshot.batteryDrawWatts), unit: "W",
                     detail: battery.minutesRemaining.map { "\(Fmt.duration(minutes: $0)) left" } ?? "Estimating time left",
                     color: Theme.battery, spark: history.map { max(0, -$0.battery) },
                     help: "How fast the battery is draining right now.")
        } else {
            StatTile(title: "Power in", symbol: "powerplug.fill", value: "–", unit: "",
                     detail: "No power data", color: Theme.powerIn)
        }
    }
}

struct PluggedInCard: View {
    let snapshot: Snapshot
    let openDevices: () -> Void

    var body: some View {
        Card("Plugged in now", symbol: "cable.connector", trailing: {
            Button(action: openDevices) {
                HStack(spacing: 3) {
                    Text("Details")
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.mac)
            }
            .buttonStyle(.plain)
        }) {
            VStack(spacing: 2) {
                if let charger = snapshot.charger {
                    HoverRow(action: openDevices) {
                        row(symbol: "powerplug.fill", color: Theme.powerIn, title: charger.displayName,
                            detail: "Charging your Mac\(portSuffix(charger.portID))",
                            value: Fmt.watts(snapshot.telemetry?.inputWatts ?? 0))
                    }
                }
                ForEach(snapshot.devices) { device in
                    HoverRow(action: openDevices) {
                        row(symbol: device.kind.symbol, color: device.kind.color, title: device.name,
                            detail: "\(snapshot.port(for: device)?.shortTitle ?? "USB") · \(device.speedLabel)",
                            value: snapshot.powerOut(for: device).map { Fmt.watts($0.watts) } ?? "–")
                    }
                }
                if snapshot.charger == nil && snapshot.devices.isEmpty {
                    Text("Nothing is plugged in. Connect a phone, drive or charger and it shows up here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, -10)
        }
    }

    private func portSuffix(_ portID: String?) -> String {
        guard let port = snapshot.ports.first(where: { $0.id == portID }) else { return "" }
        return " · \(port.shortTitle)"
    }

    private func row(symbol: String, color: Color, title: String, detail: String, value: String) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

struct ActivityCard: View {
    let events: [ActivityEvent]
    var limit = 30

    var body: some View {
        Card("Recent activity", symbol: "clock.arrow.circlepath",
             help: "Plug-ins, unplugs, charger changes and warnings since PowerDeck opened.") {
            VStack(alignment: .leading, spacing: 12) {
                if events.isEmpty {
                    Text("Nothing yet. Plug something in and it'll appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(events.prefix(limit)) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: event.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(event.kind.color)
                            .frame(width: 26, height: 26)
                            .background(event.kind.color.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            Text(event.detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Text(event.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: events.first?.id)
        }
    }
}
