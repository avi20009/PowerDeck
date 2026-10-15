import AppKit
import SwiftUI

@main
@MainActor
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--snapshot"), args.indices.contains(flag + 1) {
            Snapshotter.renderPNGs(into: args[flag + 1])
        } else if args.contains("--dump") {
            Snapshotter.dump()
        } else {
            PowerDeckApp.main()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let showInDock = UserDefaults.standard.object(forKey: Prefs.showInDock) as? Bool ?? true
        if !showInDock {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

struct PowerDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Prefs.menuBarStyle) private var menuBarStyle = MenuBarStyle.power.rawValue
    @State private var monitor: Monitor

    init() {
        let monitor = Monitor()
        monitor.start()
        _monitor = State(initialValue: monitor)
    }

    var body: some Scene {
        Window("PowerDeck", id: "dashboard") {
            DashboardView(monitor: monitor)
                .frame(minWidth: 1200, minHeight: 720)
                .preferredColorScheme(.dark)
                .containerBackground(for: .window) { BackgroundGlow() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1380, height: 920)

        MenuBarExtra {
            MenuBarView(monitor: monitor)
                .preferredColorScheme(.dark)
        } label: {
            let style = MenuBarStyle(rawValue: menuBarStyle) ?? .power
            if style == .iconOnly {
                Image(systemName: monitor.menuBarSymbol)
            } else {
                Text("\(Image(systemName: monitor.menuBarSymbol)) \(monitor.menuBarTitle(style))")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(monitor: monitor)
                .preferredColorScheme(.dark)
        }
    }
}

/// Command-line modes used to check the readers and the layout without opening a window.
@MainActor
enum Snapshotter {
    static func renderPNGs(into directory: String) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let monitor = sampledMonitor(samples: 10)
        for tab in DashboardTab.allCases {
            let view = DashboardContent(monitor: monitor, tab: .constant(tab))
                .padding(28)
                .frame(width: 1380)
                .background(BackgroundGlow())
            write(view, to: "\(directory)/\(tab.rawValue).png")
        }
        write(MenuBarView(monitor: monitor), to: "\(directory)/menubar.png")
        // The alert PowerDeck shows when this device is plugged in, built the same way Monitor builds it.
        if let snapshot = monitor.snapshot, let device = snapshot.devices.first {
            let event = ActivityEvent(date: snapshot.date, kind: .connected, title: "\(device.name) connected",
                                      detail: "\(device.vendor) · \(snapshot.port(for: device)?.shortTitle ?? "a port") · \(device.generation)",
                                      symbol: device.kind.symbol)
            write(ToastView(event: event) {}.padding(30).background(Theme.background), to: "\(directory)/toast.png")
        }
    }

    private static func write<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, .dark)
            .environment(\.staticRender, true))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("Rendering \(path) failed\n".utf8))
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("Wrote \(path) (\(image.width)×\(image.height) px)")
        } catch {
            FileHandle.standardError.write(Data("Could not write \(path): \(error)\n".utf8))
        }
    }

    static func dump() {
        let monitor = sampledMonitor(samples: 3)
        guard let s = monitor.snapshot else { print("No data"); return }
        print("Mac: \(s.mac.computerName) · \(s.mac.modelName) (\(s.mac.modelIdentifier)) · \(s.mac.chip)")
        if let c = s.charger {
            let profiles = c.profiles.map { "\(Fmt.roundVolts($0.volts))/\(Fmt.roundAmps($0.amps))" }.joined(separator: " ")
            print("Charger: \(c.displayName) · \(c.ratedWatts) W · contract \(c.contractVolts) V × \(c.contractAmps) A · \(c.portID ?? "?") · offers \(profiles)")
        } else {
            print("Charger: none")
        }
        if let t = s.telemetry {
            print("Telemetry: in \(t.inputWatts) W (\(t.inputVolts) V × \(t.inputAmps) A) · system \(t.systemWatts) W · loss \(t.conversionLossWatts) W")
        }
        if let b = s.battery {
            print("Battery: \(b.percent)% · \(b.volts) V × \(b.amps) A = \(Fmt.signedWatts(b.watts)) · health \(Fmt.number(b.healthPercent))% · cycles \(b.cycleCount)/\(b.designCycleCount) · \(b.minutesRemaining.map { "\($0) min" } ?? "–")")
        }
        print("Mac load \(Fmt.watts(s.macWatts)) · devices \(Fmt.watts(s.accessoryWatts))")
        for p in s.ports {
            let out = p.powerOut.map { "\($0.watts) W @ \($0.volts) V × \($0.amps) A of \($0.budgetWatts) W" } ?? "–"
            print("Port \(p.id): \(p.role.label) · transports \(p.activeTransports) · partner \(p.partnerBrand ?? "–") \(p.partnerName ?? "") · out \(out) · devices \(p.devices.map(\.name))")
        }
        for d in s.devices {
            print("Device: \(d.name) by \(d.vendor) [\(d.kind.label)] on \(d.portID ?? "?") · \(d.generation) \(d.speedLabel)")
            for line in DeviceAnalyzer.lines(for: d, in: s) { print("    - \(line.text)") }
        }
        print("System: CPU \(Fmt.percent(s.system.cpuUsage)) on \(s.system.coreUsage.count) cores · memory \(Fmt.gigabytes(s.system.memoryUsed))/\(Fmt.gigabytes(s.system.memoryTotal)) · pressure \(s.system.memoryPressure.label) · \(s.system.thermalState.label)")
        for p in s.topProcesses { print("Process: \(p.name) \(String(format: "%.1f", p.cpuPercent))%") }
        for i in monitor.insights { print("[\(i.severity)] \(i.title): \(i.detail)") }
        let session = monitor.session
        print("Session: charger \(Fmt.wattHours(session.fromChargerWh)) · battery +\(Fmt.wattHours(session.intoBatteryWh)) / −\(Fmt.wattHours(session.fromBatteryWh)) · devices \(Fmt.wattHours(session.toDevicesWh))")
        for e in monitor.events { print("Event: \(e.title) — \(e.detail)") }
    }

    private static func sampledMonitor(samples: Int) -> Monitor {
        let monitor = Monitor()
        for index in 0..<samples {
            monitor.refresh()
            if index < samples - 1 { Thread.sleep(forTimeInterval: 0.6) }
        }
        return monitor
    }
}
