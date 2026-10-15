import SwiftUI

struct DevicesTab: View {
    let monitor: Monitor
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PortsSection(snapshot: snapshot)
                .appear(0)
            DevicesSection(snapshot: snapshot, session: monitor.session)
                .appear(1)
            ActivityCard(events: monitor.events, limit: 25)
                .appear(2)
        }
    }
}

struct PortsSection: View {
    let snapshot: Snapshot

    var body: some View {
        let inUse = snapshot.ports.filter { $0.role != .empty }.count
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ports", symbol: "cable.connector.horizontal",
                          subtitle: "\(inUse) of \(snapshot.ports.count) in use")
            HStack(alignment: .top, spacing: 16) {
                ForEach(snapshot.ports) { port in
                    PortCard(port: port, charger: snapshot.charger, telemetry: snapshot.telemetry)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PortCard: View {
    let port: PortInfo
    let charger: ChargerInfo?
    let telemetry: PowerTelemetry?

    var body: some View {
        Card(port.title, symbol: port.isMagSafe ? "powerplug.fill" : "cable.connector",
             help: port.isMagSafe ? "Apple's magnetic charging port." : "macOS's own numbering for this port.",
             trailing: {
                 Pill(text: port.role.label, color: port.role.color)
             }) {
            VStack(alignment: .leading, spacing: 10) {
                roleContent
                Spacer(minLength: 0)
                Divider().overlay(Theme.border)
                Text(port.capabilities.joined(separator: "  ·  "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var deviceNames: String {
        port.devices.isEmpty ? "Unidentified device" : port.devices.map(\.name).joined(separator: ", ")
    }

    @ViewBuilder private var roleContent: some View {
        switch port.role {
        case .chargingMac:
            BigReadout(value: Fmt.number(telemetry?.inputWatts ?? 0), unit: "W in", color: Theme.powerIn)
            Text(charger?.displayName ?? "Charger").font(.system(size: 13, weight: .medium))
            if let charger {
                Text("Agreed on \(Fmt.roundVolts(charger.contractVolts)) × \(Fmt.roundAmps(charger.contractAmps)) · \(Int(charger.ratedWatts)) W max")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        case .poweringDevice:
            if let power = port.powerOut {
                let share = power.budgetWatts > 0 ? power.watts / power.budgetWatts : 0
                BigReadout(value: Fmt.number(power.watts), unit: "W out", color: Theme.accessory)
                Text(deviceNames).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("\(Fmt.volts(power.volts)) · \(Fmt.amps(power.amps))")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                MeterBar(fraction: share, color: Theme.accessory)
                Text("\(Fmt.percent(share)) of the \(Int(power.budgetWatts)) W this port can supply")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        case .data:
            BigReadout(value: Fmt.linkSpeed(port.devices.map(\.linkSpeed).max() ?? 0), unit: "link", color: Theme.mac)
            Text(deviceNames).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Text("Exchanging data, not drawing noticeable power")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        case .attached:
            Text("Something is attached")
                .font(.system(size: 14, weight: .medium))
            Text("It isn't drawing power or exchanging data. It may be a passive adapter or an unpowered cable.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .empty:
            Text("Nothing plugged in")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(port.isMagSafe ? "Plug in a MagSafe cable for the fastest charging." : "Free for a phone, drive, display or charger.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

struct DevicesSection: View {
    let snapshot: Snapshot
    let session: SessionStats

    var body: some View {
        let devices = snapshot.devices
        let rows = stride(from: 0, to: devices.count, by: 2).map { Array(devices[$0..<min($0 + 2, devices.count)]) }
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Connected devices", symbol: "externaldrive.connected.to.line.below",
                          subtitle: devices.isEmpty ? "none detected" : "\(devices.count) detected")
            if devices.isEmpty {
                PlugInHint(title: "No USB devices connected",
                           detail: "Plug in your phone, a drive or any accessory. PowerDeck identifies it, shows how much power it pulls, and tells you what it's capable of.")
                    .frame(height: 150)
            } else {
                VStack(spacing: 16) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(rows[index]) { device in
                                DeviceCard(device: device, snapshot: snapshot, energyWh: session.perDeviceWh[device.id])
                                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                            }
                            if rows[index].count == 1 {
                                PlugInHint(title: "Plug in another device",
                                           detail: "Phones, drives, hubs and chargers show up here instantly with their power draw and capabilities.")
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: devices.map(\.id))
            }
        }
    }
}

struct DeviceCard: View {
    let device: USBDevice
    let snapshot: Snapshot
    let energyWh: Double?

    @State private var bounce = false

    var body: some View {
        let port = snapshot.port(for: device)
        let power = snapshot.powerOut(for: device)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                IconTile(symbol: device.kind.symbol, color: device.kind.color, size: 52)
                    .symbolEffect(.bounce, value: bounce)
                    .onAppear { bounce.toggle() }
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name).font(.system(size: 17, weight: .semibold))
                    Text("\(device.vendor) · \(device.kind.label)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let port {
                    Pill(text: port.shortTitle, color: Theme.textSecondary, symbol: "cable.connector")
                }
            }
            HStack(spacing: 10) {
                MetricBox(label: "Data link", value: device.speedLabel, detail: device.generation)
                MetricBox(label: "Power draw",
                          value: power.map { Fmt.watts($0.watts) } ?? "–",
                          detail: power.map { "\(Fmt.volts($0.volts)) · \(Fmt.amps($0.amps))" } ?? "not measured")
                MetricBox(label: "Port can give",
                          value: port?.powerOut.map { "\(Int($0.budgetWatts)) W" } ?? (port?.isMagSafe == false ? "15 W" : "–"),
                          detail: port?.powerOut.map { "\(Fmt.roundVolts($0.budgetVolts)) × \(Fmt.roundAmps($0.budgetAmps)) max" } ?? "USB-C standard")
                MetricBox(label: "Delivered",
                          value: energyWh.map(Fmt.wattHours) ?? "–",
                          detail: "since connected")
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(DeviceAnalyzer.lines(for: device, in: snapshot)) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: line.tone.symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(line.tone.color)
                            .frame(width: 16)
                        Text(line.text)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("USB ID \(String(format: "%04X:%04X", device.vendorID, device.productID))")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
        }
        .cardStyle()
    }
}

struct PlugInHint: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 22))
                .foregroundStyle(Theme.textTertiary)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}
