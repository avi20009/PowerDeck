import SwiftUI

/// The compact panel that drops down from the menu bar icon.
struct MenuBarView: View {
    let monitor: Monitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = monitor.snapshot {
                let status = PowerStatus.describe(s)
                HStack(spacing: 8) {
                    LiveDot()
                    Text("PowerDeck").font(.system(size: 14, weight: .bold))
                    Spacer()
                    Pill(text: status.text, color: status.color, symbol: status.symbol)
                }
                HStack(spacing: 8) {
                    if s.charger != nil, let t = s.telemetry {
                        MiniStat(label: "Power in", value: Fmt.watts(t.inputWatts), color: Theme.powerIn)
                    } else if s.battery != nil {
                        MiniStat(label: "Draw", value: Fmt.watts(s.batteryDrawWatts), color: Theme.battery)
                    }
                    MiniStat(label: "Your Mac", value: Fmt.watts(s.macWatts), color: Theme.mac)
                    if let battery = s.battery {
                        MiniStat(label: "Battery", value: "\(battery.percent)%", color: Theme.battery)
                    }
                }
                if !s.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SmallLabel("Plugged in")
                        ForEach(s.devices) { device in
                            HStack(spacing: 8) {
                                Image(systemName: device.kind.symbol)
                                    .foregroundStyle(device.kind.color)
                                    .frame(width: 18)
                                Text(device.name).font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                let value = s.powerOut(for: device).map { Fmt.watts($0.watts) } ?? device.speedLabel
                                Text(value)
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                if let top = monitor.insights.first {
                    InsightRow(insight: top, compact: true)
                }
            }
            Divider().overlay(Theme.border)
            HStack(spacing: 8) {
                Button {
                    openWindow(id: "dashboard")
                    NSApp.activate()
                } label: {
                    Label("Open Dashboard", systemImage: "rectangle.grid.2x2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.powerIn, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                SettingsLink {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.card, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 340)
        .foregroundStyle(Theme.textPrimary)
        .background(Theme.background)
    }
}

private struct MiniStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SmallLabel(label)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .valueFade(value)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
