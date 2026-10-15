import Foundation

/// Turns a snapshot into plain-language advice, most urgent first.
enum InsightEngine {
    static func evaluate(_ s: Snapshot) -> [Insight] {
        var out: [Insight] = []
        addPower(s, to: &out)
        addBattery(s, to: &out)
        addPorts(s, to: &out)
        addSystem(s, to: &out)
        if !out.contains(where: { $0.severity >= .warning }) {
            out.append(Insight(.good, "Everything looks healthy", "No power, heat or memory problems right now."))
        }
        // Stable: most severe first, otherwise in the order the checks produced them.
        return out.enumerated()
            .sorted { ($0.element.severity, -$0.offset) > ($1.element.severity, -$1.offset) }
            .map(\.element)
    }

    private static func addPower(_ s: Snapshot, to out: inout [Insight]) {
        guard let b = s.battery else { return }

        if s.isMeasuring {
            out.append(Insight(.info, "On battery · \(b.percent)%",
                               "Just switched to battery, so macOS is re-measuring power use. The numbers settle within a minute."))
            return
        }

        guard let charger = s.charger else {
            let draw = s.batteryDrawWatts
            let eta = b.minutesRemaining.map { "about \(Fmt.duration(minutes: $0)) left" } ?? "still estimating time left"
            out.append(Insight(b.percent <= 20 ? .warning : .info, "On battery · \(b.percent)%",
                               "Drawing \(Fmt.watts(draw)), \(eta) at this rate."))
            if s.macWatts > (s.mac.isMacBookAir ? 12 : 25), let top = s.topProcesses.first, top.cpuPercent >= 25 {
                out.append(Insight(.tip, "Heavy battery use",
                                   "Your Mac is using \(Fmt.watts(s.macWatts)) and \(top.name) is the busiest app (\(Int(top.cpuPercent))% CPU). Quitting apps you don't need will stretch your battery."))
            }
            if s.accessoryWatts > 1 {
                let who = s.devices.count == 1 ? "Your \(s.devices[0].name)" : "Your plugged-in devices"
                let comparison = s.accessoryWatts > s.macWatts ? ", more than your Mac itself" : ""
                var detail = "\(who) \(s.devices.count == 1 ? "is" : "are") drawing \(Fmt.watts(s.accessoryWatts)) from your battery\(comparison)."
                // Start from macOS's own estimate so this agrees with the "time left" shown elsewhere.
                let energy = s.batteryEnergyLeftWh
                if draw > 0, s.macWatts > 0.5, let now = b.minutesRemaining ?? (energy > 0 ? Int(energy / draw * 60) : nil) {
                    let without = Int(Double(now) * draw / s.macWatts)
                    if without - now >= 10 {
                        detail += " Unplugging would stretch your battery from about \(Fmt.duration(minutes: now)) to \(Fmt.duration(minutes: min(without, 24 * 60)))."
                    }
                }
                out.append(Insight(.tip, "\(s.devices.count == 1 ? s.devices[0].name : "Devices") \(s.devices.count == 1 ? "is" : "are") using your battery", detail))
            }
            return
        }

        let input = s.telemetry?.inputWatts ?? 0
        let demand = s.telemetry?.systemWatts ?? 0
        let name = charger.shortName

        if s.chargerIdle {
            let waited = s.chargerConnectedSince.map { s.date.timeIntervalSince($0) } ?? .infinity
            if waited < 90 {
                out.append(Insight(.info, "Charger connected, starting up",
                                   "Your Mac sees the \(name) and is finishing the power handshake. Power usually starts flowing within a minute; until then you're on battery."))
            } else {
                out.append(Insight(.warning, "Charger connected, but no power is flowing",
                                   "Your Mac sees the \(name) but isn't getting any power from it, so it's running on battery. Check the charger is plugged into a working outlet, or try another cable or port."))
            }
            return
        }

        if b.isDischarging {
            out.append(Insight(.critical, "Battery draining while plugged in",
                               "Your Mac needs \(Fmt.watts(demand)) but the \(name) can't keep up, so the battery is covering \(Fmt.watts(-b.watts)). Use a higher-wattage USB-C charger or unplug accessories."))
        } else if charger.ratedWatts > 0, demand > charger.ratedWatts * 0.85 {
            out.append(Insight(.warning, "Charger is near its limit",
                               "Your Mac is using \(Fmt.watts(demand)) of the \(name)'s \(Int(charger.ratedWatts)) W, leaving little for the battery. Heavy work will charge slowly."))
        }

        let recommended = s.mac.isMacBookAir ? 30.0 : 60.0
        if charger.ratedWatts > 0, charger.ratedWatts < recommended {
            out.append(Insight(.warning, "Low-wattage charger",
                               "\(Int(charger.ratedWatts)) W is below the \(Int(recommended)) W Apple recommends for this Mac. Expect slow charging under load."))
        }

        if b.isCharging, b.watts > 0.05 {
            let accessories = s.accessoryWatts > 0.05 ? ", \(Fmt.watts(s.accessoryWatts)) powers accessories" : ""
            let eta = b.minutesRemaining.map { " Full in about \(Fmt.duration(minutes: $0))." } ?? ""
            out.append(Insight(.good, "Charging at \(Fmt.watts(b.watts))",
                               "Your \(name) is supplying \(Fmt.watts(input)): \(Fmt.watts(s.macWatts)) runs your Mac\(accessories) and \(Fmt.watts(b.watts)) fills the battery.\(eta)"))
        } else if b.isFullyCharged || b.percent >= 100 {
            out.append(Insight(.good, "Fully charged",
                               "Your Mac is running straight from the \(name) and the battery is resting."))
        } else if !b.isDischarging {
            out.append(Insight(.info, "Charging on hold at \(b.percent)%",
                               "macOS paused charging. That's usually Optimized Battery Charging holding near 80% to protect the battery, or the battery is warm. Nothing is wrong."))
        }

        if b.slowChargingReason != 0 || b.thermallyLimited {
            out.append(Insight(.warning, "Charging slowed by macOS",
                               "Charging speed is being limited, usually because the Mac is warm. Keep it on a hard surface and out of direct sun."))
        }
    }

    private static func addBattery(_ s: Snapshot, to out: inout [Insight]) {
        guard let b = s.battery, b.designCapacity > 0 else { return }
        let health = Int(b.healthPercent.rounded())
        if b.healthPercent < 80 {
            out.append(Insight(.warning, "Battery service recommended",
                               "It now holds \(health)% of its original capacity after \(b.cycleCount) cycles. Apple considers a battery worn below 80%; a replacement restores battery life."))
        } else {
            let verdict = health >= 90 ? "in great shape" : "aging normally"
            out.append(Insight(.good, "Battery health \(health)%",
                               "\(b.cycleCount) of \(b.designCycleCount) rated charge cycles used, \(verdict)."))
        }
    }

    private static func addPorts(_ s: Snapshot, to out: inout [Insight]) {
        for port in s.ports {
            if port.overcurrentCount > 0 {
                out.append(Insight(.warning, "\(port.shortTitle) cut power \(port.overcurrentCount)× to protect your Mac",
                                   "That happens when a device or cable tries to draw too much. If it keeps happening, swap the cable or use the other port."))
            }
            if port.role == .poweringDevice, port.devices.isEmpty, let power = port.powerOut {
                out.append(Insight(.tip, "Charge-only connection on \(port.shortTitle)",
                                   "Something is drawing \(Fmt.watts(power.watts)) but isn't showing up as a USB device. The cable may be charge-only, or a phone may be locked or waiting for you to tap Trust."))
            }
        }

        for device in s.devices where device.kind.isPhoneLike {
            if let power = s.powerOut(for: device), let port = s.port(for: device), power.watts >= 0.1, power.watts < 5 {
                out.append(Insight(.tip, "\(device.name) is charging slowly",
                                   "It's pulling \(Fmt.watts(power.watts)) from \(port.shortTitle); Mac ports give at most \(Int(power.budgetWatts)) W. A 20 W or stronger USB-C wall charger fills it several times faster."))
            }
            if device.linkSpeed > 0, device.linkSpeed <= 480_000_000 {
                let capable = device.kind == .iPhone ? "iPhone 15 Pro and later Pro models" : "Many recent devices"
                out.append(Insight(.tip, "\(device.name) is on a USB 2 link",
                                   "Transfers and backups are capped at 480 Mb/s. \(capable) support 10 Gb/s with a USB 3 cable."))
            }
        }

        for device in s.devices where device.kind == .storage && device.linkSpeed > 0 && device.linkSpeed <= 480_000_000 {
            out.append(Insight(.warning, "\(device.name) is running at USB 2 speed",
                               "File copies are limited to 480 Mb/s. A USB 3 or USB-C cable unlocks the drive's full speed."))
        }
    }

    private static func addSystem(_ s: Snapshot, to out: inout [Insight]) {
        let system = s.system
        if system.cpuUsage > 0.85 {
            let culprit = s.topProcesses.first.map { " \($0.name) is the busiest (\(Int($0.cpuPercent))%)." } ?? ""
            out.append(Insight(.warning, "CPU is maxed out (\(Fmt.percent(system.cpuUsage)))",
                               "Your Mac is working flat out, which drains battery and builds heat.\(culprit)"))
        } else if let top = s.topProcesses.first, top.cpuPercent > 80 {
            let advice = top.isApp
                ? "Quit it if it isn't doing something you need."
                : "It's a macOS background process and usually settles down on its own. If it stays this high for a long time, restarting your Mac helps."
            out.append(Insight(.tip, "\(top.name) is working hard",
                               "It's using \(Int(top.cpuPercent))% CPU (100% is one full core). \(advice)"))
        }

        switch system.memoryPressure {
        case .critical:
            out.append(Insight(.critical, "Memory is critically low",
                               "macOS has swapped \(Fmt.gigabytes(system.swapUsed)) to disk. Close apps or browser tabs you're not using."))
        case .warning:
            out.append(Insight(.warning, "Memory is getting tight",
                               "\(Fmt.gigabytes(system.memoryUsed)) of \(Fmt.gigabytes(system.memoryTotal, decimals: 0)) in use. Close apps or browser tabs you're not using to keep things snappy."))
        case .normal:
            break
        }

        let fanless = s.mac.isMacBookAir ? "MacBook Air has no fan, so " : ""
        switch system.thermalState {
        case .serious:
            out.append(Insight(.warning, "Your Mac is running hot",
                               "\(fanless)macOS is slowing things down to cool off. Close heavy apps and keep it on a hard surface."))
        case .critical:
            out.append(Insight(.critical, "Your Mac is overheating",
                               "\(fanless)performance is heavily throttled. Quit demanding apps and let it cool down."))
        default:
            break
        }

        if system.lowPowerMode {
            out.append(Insight(.info, "Low Power Mode is on",
                               "Performance is reduced to save energy. Turn it off in System Settings → Battery if things feel slow."))
        }
    }
}

/// Explains what a connected device can do on the port it's using.
enum DeviceAnalyzer {
    static func lines(for device: USBDevice, in s: Snapshot) -> [CapabilityLine] {
        var lines: [CapabilityLine] = []
        let port = s.port(for: device)

        if let power = s.powerOut(for: device) {
            let budget = Int(power.budgetWatts)
            let share = power.budgetWatts > 0 ? power.watts / power.budgetWatts : 0
            if device.kind.isPhoneLike {
                switch power.watts {
                case ..<0.1:
                    lines.append(.init(.info, "Not drawing power: it's probably full, or charging is paused."))
                case ..<5:
                    lines.append(.init(.tip, "Charging slowly at \(Fmt.watts(power.watts)). A 20 W+ USB-C wall charger is much faster than a Mac port (max \(budget) W)."))
                case ..<10:
                    lines.append(.init(.good, "Charging at a solid \(Fmt.watts(power.watts)) from your Mac."))
                default:
                    lines.append(.init(.good, "Charging near this port's \(budget) W maximum."))
                }
                if power.watts >= 5 {
                    lines.append(.init(.tip, "That's as fast as a Mac port goes. A 20 W+ USB-C wall charger can fast-charge most phones to about 50% in 30 minutes."))
                }
                if s.charger == nil, power.watts > 1 {
                    lines.append(.init(.info, "Your Mac is on battery, so this charge is coming out of your Mac's battery."))
                }
            } else if power.watts < 0.1 {
                lines.append(.init(.info, "Not drawing meaningful power right now."))
            } else if share > 0.85 {
                lines.append(.init(.warning, "Using \(Fmt.percent(share)) of the port's \(budget) W budget, close to its limit. A powered hub or wall charger is safer."))
            } else {
                lines.append(.init(.good, "Drawing \(Fmt.watts(power.watts)), comfortably inside the port's \(budget) W budget."))
            }
        } else if let port, port.devices.count > 1 {
            lines.append(.init(.info, "Shares \(port.shortTitle) with \(port.devices.count - 1) other device(s); power is measured per port."))
        } else {
            lines.append(.init(.info, "Not drawing power from your Mac (self-powered or idle)."))
        }

        let slowLink = device.linkSpeed > 0 && device.linkSpeed <= 480_000_000
        switch device.kind {
        case .iPhone:
            lines.append(slowLink
                ? .init(.tip, "USB 2 link (480 Mb/s). iPhone 15 Pro and newer Pro models can do 10 Gb/s with a USB 3 cable, up to 20× faster.")
                : .init(.good, "Fast \(device.speedLabel) link, great for backups and photo imports."))
        case .iPad, .phone:
            lines.append(slowLink
                ? .init(.tip, "USB 2 link (480 Mb/s). Many recent models support 10 Gb/s with a USB 3 cable.")
                : .init(.good, "Fast \(device.speedLabel) link for file transfers."))
        case .storage:
            lines.append(slowLink
                ? .init(.warning, "Stuck at USB 2 speed. Use a USB 3 / USB-C cable for full-speed copies.")
                : .init(.good, "Fast \(device.speedLabel) link for file transfers."))
        case .hub:
            lines.append(.init(.info, "Hub link is \(device.speedLabel); everything plugged into it shares that bandwidth."))
        case .charger, .wearable, .keyboard, .mouse, .audio, .gameController, .watch:
            lines.append(.init(.info, "\(device.generation) (\(device.speedLabel)) is all this kind of device needs."))
        case .camera, .display, .other:
            lines.append(.init(.info, "Connected at \(device.generation) (\(device.speedLabel))."))
        }

        if let port, port.supportedTransports.contains("CIO"), slowLink, device.kind == .storage || device.kind == .hub {
            lines.append(.init(.tip, "\(port.shortTitle) supports up to 40 Gb/s, so the cable or device is the bottleneck."))
        }
        return lines
    }
}
