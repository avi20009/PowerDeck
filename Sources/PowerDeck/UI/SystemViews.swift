import Charts
import SwiftUI

struct SystemTab: View {
    let monitor: Monitor
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                CPUCard(system: snapshot.system, chip: snapshot.mac.chip, history: monitor.history)
                MemoryCard(system: snapshot.system)
                    .frame(width: 430)
            }
            .fixedSize(horizontal: false, vertical: true)
            .appear(0)
            HStack(alignment: .top, spacing: 16) {
                TopAppsCard(processes: snapshot.topProcesses)
                ThermalCard(system: snapshot.system, mac: snapshot.mac)
                    .frame(width: 430)
            }
            .fixedSize(horizontal: false, vertical: true)
            .appear(1)
        }
    }
}

struct CPUCard: View {
    let system: SystemStats
    let chip: String
    let history: [PowerSample]

    var body: some View {
        Card("Processor", symbol: "cpu",
             help: "How busy your Mac's processor is. Each bar is one core; short bursts to 100% are normal.",
             trailing: { Pill(text: chip, color: Theme.textSecondary) }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.percent(system.cpuUsage))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .valueFade(Int(system.cpuUsage * 100))
                    Text("busy across \(system.coreUsage.count) cores")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(system.coreUsage.enumerated()), id: \.offset) { item in
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [Theme.tip, Theme.mac], startPoint: .top, endPoint: .bottom))
                                    .frame(height: max(3, 56 * item.element))
                            }
                            .frame(height: 56)
                            Text("\(item.offset + 1)")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .animation(.smooth(duration: 0.35), value: system.coreUsage)
                SmallLabel("Last 5 minutes")
                Chart(history) { sample in
                    AreaMark(x: .value("Time", sample.date), y: .value("CPU", sample.cpu * 100))
                        .foregroundStyle(LinearGradient(colors: [Theme.tip.opacity(0.35), Theme.tip.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", sample.date), y: .value("CPU", sample.cpu * 100))
                        .foregroundStyle(Theme.tip)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%") } }
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 120)
            }
        }
    }
}

struct MemoryCard: View {
    let system: SystemStats

    var body: some View {
        let fraction = Double(system.memoryUsed) / Double(max(system.memoryTotal, 1))
        Card("Memory", symbol: "memorychip",
             help: "macOS keeps memory busy on purpose to make things fast. Pressure is what tells you if you're actually running out.",
             trailing: {
                 Pill(text: "Pressure \(system.memoryPressure.label.lowercased())", color: system.memoryPressure.color)
             }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 20) {
                    RingGauge(fraction: fraction, color: system.memoryPressure.color,
                              value: Fmt.percent(fraction), caption: "in use", size: 120)
                    VStack(spacing: 10) {
                        KeyValueRow(key: "In use", value: Fmt.gigabytes(system.memoryUsed))
                        KeyValueRow(key: "Installed", value: Fmt.gigabytes(system.memoryTotal, decimals: 0))
                        KeyValueRow(key: "Swapped to disk", value: system.swapUsed > 0 ? Fmt.gigabytes(system.swapUsed) : "None")
                    }
                }
                Text(explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var explanation: String {
        switch system.memoryPressure {
        case .normal:
            "Plenty of room. A high \"in use\" number is normal: macOS fills spare memory with caches to keep apps fast."
        case .warning:
            "Memory is getting tight, so macOS is compressing it and using the disk. Closing apps or browser tabs you're not using will help."
        case .critical:
            "Your Mac is out of memory and leaning hard on the disk, which slows everything down. Quit apps you don't need."
        }
    }
}

struct TopAppsCard: View {
    let processes: [ProcessUsage]

    var body: some View {
        let ceiling = max(100, processes.first?.cpuPercent ?? 0)
        Card("Busiest apps right now", symbol: "list.number",
             help: "Apps using the most CPU. 100% means one full core, so busy apps can go above 100%. System processes owned by macOS aren't listed.") {
            VStack(alignment: .leading, spacing: 12) {
                if processes.isEmpty {
                    Text("Nothing is using noticeable CPU right now.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(processes) { process in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(process.name)
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text("\(Int(process.cpuPercent.rounded()))%")
                                .font(.system(size: 12.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                        MeterBar(fraction: process.cpuPercent / ceiling, color: Theme.mac, height: 5)
                    }
                }
            }
            .animation(.smooth, value: processes.map(\.id))
        }
    }
}

struct ThermalCard: View {
    let system: SystemStats
    let mac: MacIdentity

    var body: some View {
        Card("Temperature & power mode", symbol: "thermometer.medium",
             help: "macOS reports heat as a level rather than degrees. When it gets hot, the Mac slows itself down to cool off.") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    IconTile(symbol: thermalSymbol, color: system.thermalState.color, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(system.thermalState.label)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(system.thermalState.color)
                        Text(thermalExplanation)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().overlay(Theme.border)
                VStack(spacing: 10) {
                    KeyValueRow(key: "Low Power Mode", value: system.lowPowerMode ? "On" : "Off")
                    KeyValueRow(key: "Cooling", value: mac.isMacBookAir ? "Fanless (silent)" : "Fans")
                }
            }
        }
    }

    private var thermalSymbol: String {
        switch system.thermalState {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        default: "thermometer.high"
        }
    }

    private var thermalExplanation: String {
        switch system.thermalState {
        case .nominal: "Running cool, with no slowdown."
        case .fair: "A little warm, which is normal under load."
        case .serious: "Hot. macOS is slowing things down to cool off."
        case .critical: "Very hot. Performance is heavily reduced."
        @unknown default: "Temperature level unknown."
        }
    }
}
