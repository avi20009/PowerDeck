import Charts
import SwiftUI

struct PowerTab: View {
    let monitor: Monitor
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                BatteryCard(battery: snapshot.battery)
                ChargerCard(charger: snapshot.charger, telemetry: snapshot.telemetry,
                            ports: snapshot.ports, mac: snapshot.mac)
            }
            .fixedSize(horizontal: false, vertical: true)
            .appear(0)
            PowerFlowCard(snapshot: snapshot)
                .appear(1)
            HStack(alignment: .top, spacing: 16) {
                LiveChartCard(history: monitor.history)
                SessionCard(session: monitor.session, now: snapshot.date)
                    .frame(width: 400)
            }
            .fixedSize(horizontal: false, vertical: true)
            .appear(2)
        }
    }
}

struct PowerFlowCard: View {
    let snapshot: Snapshot

    private struct Segment: Identifiable {
        let id: String
        let watts: Double
        let color: Color
        let note: String
    }

    private var segments: [Segment] {
        var result = [Segment(id: "Mac", watts: snapshot.macWatts, color: Theme.mac, note: "runs your Mac")]
        if let battery = snapshot.battery, battery.watts > 0.05 {
            result.append(Segment(id: "Battery", watts: battery.watts, color: Theme.battery, note: "charges the battery"))
        }
        if snapshot.accessoryWatts > 0.01 {
            result.append(Segment(id: "Devices", watts: snapshot.accessoryWatts, color: Theme.accessory, note: "powers USB devices"))
        }
        if snapshot.charger != nil, let loss = snapshot.telemetry?.conversionLossWatts, loss > 0.05 {
            result.append(Segment(id: "Heat", watts: loss, color: Theme.loss, note: "lost in conversion"))
        }
        return result
    }

    private var headline: String {
        if let charger = snapshot.charger, let t = snapshot.telemetry {
            var text = "\(Fmt.watts(t.inputWatts)) coming in from your \(charger.shortName)"
            if let battery = snapshot.battery, battery.isDischarging {
                text += " + \(Fmt.watts(-battery.watts)) from the battery"
            }
            return text
        }
        if snapshot.battery != nil {
            return "\(Fmt.watts(snapshot.batteryDrawWatts)) coming out of the battery"
        }
        return "Live power split"
    }

    var body: some View {
        let parts = segments
        let total = max(parts.reduce(0) { $0 + $1.watts }, 0.01)
        Card("Where your power goes", symbol: "chart.bar.xaxis",
             help: "How the power coming in right now is split up.",
             trailing: {
                 Text(headline).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
             }) {
            VStack(alignment: .leading, spacing: 16) {
                GeometryReader { geo in
                    let available = geo.size.width - CGFloat(max(parts.count - 1, 0)) * 3
                    HStack(spacing: 3) {
                        ForEach(parts) { part in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(part.color.gradient)
                                .frame(width: max(3, available * part.watts / total))
                        }
                    }
                    .animation(.smooth(duration: 0.35), value: parts.map(\.watts))
                }
                .frame(height: 28)
                HStack(alignment: .top, spacing: 40) {
                    ForEach(parts) { part in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle().fill(part.color).frame(width: 8, height: 8)
                                Text(part.id)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Text(Fmt.watts(part.watts))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("\(Fmt.percent(part.watts / total)) · \(part.note)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}

struct LiveChartCard: View {
    let history: [PowerSample]

    private struct Point: Identifiable {
        let date: Date
        let series: String
        let watts: Double
        var id: String { "\(series)-\(date.timeIntervalSinceReferenceDate)" }
    }

    private static let seriesNames = ["Power in", "Mac", "Battery", "Devices"]
    private static let seriesColors = [Theme.powerIn, Theme.mac, Theme.battery, Theme.accessory]

    private var points: [Point] {
        history.flatMap { sample in
            [
                Point(date: sample.date, series: "Power in", watts: sample.input),
                Point(date: sample.date, series: "Mac", watts: sample.mac),
                Point(date: sample.date, series: "Battery", watts: sample.battery),
                Point(date: sample.date, series: "Devices", watts: sample.accessories),
            ]
        }
    }

    var body: some View {
        Card("Live power · last 5 min", symbol: "waveform.path.ecg",
             help: "Watts over time. Battery goes below zero when it's draining.",
             trailing: { legend }) {
            Chart(points) { point in
                LineMark(x: .value("Time", point.date), y: .value("Watts", point.watts))
                    .foregroundStyle(by: .value("Series", point.series))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale(domain: Self.seriesNames, range: Self.seriesColors)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let watts = value.as(Double.self) {
                            Text("\(Int(watts)) W")
                        }
                    }
                    .foregroundStyle(Theme.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(minHeight: 240)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(Array(zip(Self.seriesNames, Self.seriesColors)), id: \.0) { name, color in
                HStack(spacing: 5) {
                    Capsule().fill(color).frame(width: 12, height: 3)
                    Text(name).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

struct InsightsCard: View {
    let insights: [Insight]
    var limit: Int? = nil

    var body: some View {
        let problems = insights.filter { $0.severity >= .warning }.count
        let tips = insights.filter { $0.severity == .tip }.count
        let shown = limit.map { Array(insights.prefix($0)) } ?? insights
        Card("What to do", symbol: "sparkles",
             help: "Plain-language advice based on what PowerDeck sees right now. Most urgent first.",
             trailing: {
                 if problems > 0 {
                     Pill(text: "\(problems) to check", color: Theme.warning, symbol: "exclamationmark.triangle.fill")
                 }
                 if tips > 0 {
                     Pill(text: "\(tips) tip\(tips == 1 ? "" : "s")", color: Theme.tip, symbol: "lightbulb.fill")
                 }
                 if problems == 0 && tips == 0 {
                     Pill(text: "All good", color: Theme.good, symbol: "checkmark.circle.fill")
                 }
             }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { insight in
                    InsightRow(insight: insight)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    if insight.id != shown.last?.id {
                        Divider().overlay(Theme.border)
                    }
                }
            }
            .animation(.smooth, value: shown.map(\.key))
        }
    }
}

struct SessionCard: View {
    let session: SessionStats
    let now: Date

    var body: some View {
        let minutes = Int(now.timeIntervalSince(session.start) / 60)
        Card("Since PowerDeck opened", symbol: "sum",
             help: "Energy totals measured since the app started, in watt-hours (Wh). A typical phone battery holds 12–20 Wh.") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tracking for \(Fmt.duration(minutes: minutes)), since \(session.start.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                VStack(spacing: 10) {
                    energyRow("From the charger", session.fromChargerWh, Theme.powerIn)
                    energyRow("Into the battery", session.intoBatteryWh, Theme.battery)
                    energyRow("Out of the battery", session.fromBatteryWh, Theme.warning)
                    energyRow("To USB devices", session.toDevicesWh, Theme.accessory)
                }
                Divider().overlay(Theme.border)
                KeyValueRow(key: "Highest Mac power", value: Fmt.watts(session.peakMacWatts))
            }
        }
    }

    private func energyRow(_ title: String, _ wattHours: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            KeyValueRow(key: title, value: Fmt.wattHours(wattHours))
        }
    }
}
