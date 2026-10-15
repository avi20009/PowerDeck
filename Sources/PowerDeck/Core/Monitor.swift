import Foundation
import Observation

/// Samples every reader on a fixed cadence and publishes the latest snapshot, insights, history,
/// activity log and session energy totals.
@MainActor
@Observable
final class Monitor {
    private(set) var snapshot: Snapshot?
    private(set) var insights: [Insight] = []
    private(set) var history: [PowerSample] = []
    private(set) var events: [ActivityEvent] = []
    private(set) var toasts: [ActivityEvent] = []
    private(set) var session = SessionStats(start: Date())
    private(set) var interval = Prefs.interval

    var notificationsEnabled = UserDefaults.standard.bool(forKey: Prefs.notifyDevices)

    private let identity = SystemReader.identity()
    private let cpu = CPUSampler()
    private let processes = ProcessSampler()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var chargerSince: Date?
    /// When each warning last raised an alert, so a flapping warning doesn't repeat every few seconds.
    @ObservationIgnored private var lastAlerted: [String: Date] = [:]

    static let historyWindow: TimeInterval = 300
    static let eventLimit = 50
    static let toastDuration: Duration = .seconds(6)

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // .common keeps it ticking while the user scrolls.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func setInterval(_ seconds: TimeInterval) {
        guard seconds > 0, seconds != interval else { return }
        interval = seconds
        timer?.invalidate()
        timer = nil
        start()
    }

    func refresh() {
        let power = PowerReader.read()
        let devices = USBReader.read()
        var ports = PortReader.read(outputs: power.portOutputs, onExternalPower: power.charger != nil)
        for index in ports.indices {
            ports[index].devices = devices.filter { $0.portID == ports[index].id }
        }

        var charger = power.charger
        if let port = ports.first(where: \.isChargingMac) {
            charger?.portID = port.id
            charger?.brand = port.partnerBrand
            charger?.model = port.partnerName
        }
        if charger == nil {
            chargerSince = nil
        } else if chargerSince == nil {
            chargerSince = Date()
        }

        let snapshot = Snapshot(
            date: Date(),
            mac: identity,
            charger: charger,
            battery: power.battery,
            telemetry: power.telemetry,
            ports: ports,
            devices: devices,
            system: SystemReader.stats(cpu: cpu.sample()),
            topProcesses: processes.sample(limit: 8),
            chargerConnectedSince: chargerSince
        )
        let previous = self.snapshot
        let previousInsights = insights
        self.snapshot = snapshot
        insights = InsightEngine.evaluate(snapshot)

        accumulate(from: previous, to: snapshot)
        detectEvents(from: previous, to: snapshot, previousInsights: previousInsights)

        history.append(PowerSample(
            date: snapshot.date,
            input: snapshot.charger == nil ? 0 : snapshot.telemetry?.inputWatts ?? 0,
            mac: snapshot.macWatts,
            battery: snapshot.charger == nil ? -snapshot.batteryDrawWatts : snapshot.battery?.watts ?? 0,
            accessories: snapshot.accessoryWatts,
            cpu: snapshot.system.cpuUsage,
            memory: Double(snapshot.system.memoryUsed) / Double(max(snapshot.system.memoryTotal, 1))
        ))
        let cutoff = snapshot.date.addingTimeInterval(-Self.historyWindow)
        history.removeAll { $0.date < cutoff }
    }

    func dismissToast(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    // MARK: - Session energy

    private func accumulate(from old: Snapshot?, to new: Snapshot) {
        session.peakMacWatts = max(session.peakMacWatts, new.macWatts)
        guard let old else { return }
        let seconds = new.date.timeIntervalSince(old.date)
        // Skip gaps such as sleep, where what happened in between is unknown.
        guard seconds > 0, seconds < 30 else { return }
        let hours = seconds / 3600

        if new.charger != nil {
            session.fromChargerWh += (new.telemetry?.inputWatts ?? 0) * hours
        }
        if let battery = new.battery {
            if battery.watts > 0 {
                session.intoBatteryWh += battery.watts * hours
            } else {
                session.fromBatteryWh += -battery.watts * hours
            }
        }
        session.toDevicesWh += new.accessoryWatts * hours
        for device in new.devices {
            if let power = new.powerOut(for: device) {
                session.perDeviceWh[device.id, default: 0] += power.watts * hours
            }
        }
    }

    // MARK: - Activity

    private func detectEvents(from old: Snapshot?, to new: Snapshot, previousInsights: [Insight]) {
        guard let old else {
            let count = new.devices.count
            let power = new.charger.map { "charging from \($0.shortName)" } ?? "running on battery"
            log(.info, "PowerDeck started", "\(count) device\(count == 1 ? "" : "s") connected, \(power)",
                symbol: "play.circle.fill", alert: false)
            return
        }

        let oldIDs = Set(old.devices.map(\.id))
        let newIDs = Set(new.devices.map(\.id))
        for device in new.devices where !oldIDs.contains(device.id) {
            let port = new.port(for: device)?.shortTitle ?? "a port"
            log(.connected, "\(device.name) connected", "\(device.vendor) · \(port) · \(device.generation)",
                symbol: device.kind.symbol, alert: true)
        }
        for device in old.devices where !newIDs.contains(device.id) {
            let port = old.port(for: device)?.shortTitle ?? "a port"
            let energy = session.perDeviceWh[device.id].map { ", got \(Fmt.wattHours($0)) while connected" } ?? ""
            log(.disconnected, "\(device.name) unplugged", "Was on \(port)\(energy)", symbol: "eject.fill", alert: true)
        }

        switch (old.charger, new.charger) {
        case (nil, let charger?):
            log(.power, "Charger connected", "\(charger.displayName) · \(Int(charger.ratedWatts)) W",
                symbol: "powerplug.fill", alert: true)
        case (_?, nil):
            let percent = new.battery.map { " at \($0.percent)%" } ?? ""
            log(.power, "Charger unplugged", "Now running on battery\(percent)", symbol: "battery.75percent", alert: true)
        default:
            break
        }

        if let before = old.battery, let after = new.battery, new.charger != nil,
           !(before.isFullyCharged || before.percent >= 100), after.isFullyCharged || after.percent >= 100 {
            log(.power, "Fully charged", "You can unplug any time; macOS protects the battery if you don't.",
                symbol: "battery.100percent.bolt", alert: true)
        }

        let previousWarnings = Set(previousInsights.filter { $0.severity >= .warning }.map(\.key))
        for insight in insights where insight.severity >= .warning && !previousWarnings.contains(insight.key) {
            if let last = lastAlerted[insight.key], new.date.timeIntervalSince(last) < 600 { continue }
            lastAlerted[insight.key] = new.date
            log(.warning, insight.title, insight.detail, symbol: "exclamationmark.triangle.fill", alert: true)
        }
    }

    private func log(_ kind: ActivityEvent.Kind, _ title: String, _ detail: String, symbol: String, alert: Bool) {
        let event = ActivityEvent(date: Date(), kind: kind, title: title, detail: detail, symbol: symbol)
        events.insert(event, at: 0)
        if events.count > Self.eventLimit { events.removeLast(events.count - Self.eventLimit) }

        guard alert else { return }
        toasts.append(event)
        if toasts.count > 3 { toasts.removeFirst(toasts.count - 3) }
        if notificationsEnabled { Notifier.post(event) }
        Task { [weak self] in
            try? await Task.sleep(for: Self.toastDuration)
            self?.dismissToast(event.id)
        }
    }

    // MARK: - Menu bar

    func menuBarTitle(_ style: MenuBarStyle) -> String {
        guard let s = snapshot else { return "–" }
        switch style {
        case .power:
            if s.charger != nil, let input = s.telemetry?.inputWatts, input > 0 {
                return "\(Int(input.rounded())) W"
            }
            return s.battery.map { "\($0.percent)%" } ?? "\(Int(s.macWatts.rounded())) W"
        case .battery:
            return s.battery.map { "\($0.percent)%" } ?? "–"
        case .macLoad:
            return "\(Int(s.macWatts.rounded())) W"
        case .iconOnly:
            return ""
        }
    }

    var menuBarSymbol: String {
        guard let s = snapshot, let battery = s.battery else { return "bolt.fill" }
        if s.charger != nil { return battery.isCharging ? "bolt.fill" : "powerplug.fill" }
        return Fmt.batterySymbol(battery.percent)
    }
}
