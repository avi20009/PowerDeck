import AppKit
import Darwin
import SystemConfiguration

enum SystemReader {
    static func identity() -> MacIdentity {
        let model = Sysctl.string("hw.model") ?? "Mac"
        let chip = Sysctl.string("machdep.cpu.brand_string") ?? "Apple silicon"
        return MacIdentity(
            computerName: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "This Mac",
            modelIdentifier: model,
            modelName: modelNames[model] ?? fallbackModelName(model, chip: chip),
            chip: chip,
            memoryBytes: UInt64(Sysctl.integer("hw.memsize", as: Int64.self) ?? 0)
        )
    }

    static func stats(cpu: CPULoad) -> SystemStats {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        // Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
        let page = UInt64(getpagesize())
        let appPages = UInt64(max(0, Int64(vm.internal_page_count) - Int64(vm.purgeable_count)))
        let used = result == KERN_SUCCESS
            ? (appPages + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * page
            : 0

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : 0

        let pressure: MemoryPressure = switch Sysctl.integer("kern.memorystatus_vm_pressure_level", as: Int32.self) ?? 1 {
        case 4: .critical
        case 2: .warning
        default: .normal
        }

        return SystemStats(
            cpuUsage: cpu.total,
            coreUsage: cpu.perCore,
            memoryUsed: used,
            memoryTotal: UInt64(Sysctl.integer("hw.memsize", as: Int64.self) ?? 0),
            swapUsed: swapUsed,
            memoryPressure: pressure,
            thermalState: ProcessInfo.processInfo.thermalState,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    private static func fallbackModelName(_ model: String, chip: String) -> String {
        if model.hasPrefix("MacBookAir") { return "MacBook Air (\(chip))" }
        if model.hasPrefix("MacBookPro") { return "MacBook Pro (\(chip))" }
        return "Mac (\(chip))"
    }

    private static let modelNames: [String: String] = [
        "MacBookAir10,1": "MacBook Air (M1, 2020)",
        "Mac14,2": "MacBook Air 13″ (M2, 2022)",
        "Mac14,15": "MacBook Air 15″ (M2, 2023)",
        "Mac15,12": "MacBook Air 13″ (M3, 2024)",
        "Mac15,13": "MacBook Air 15″ (M3, 2024)",
        "Mac16,12": "MacBook Air 13″ (M4, 2025)",
        "Mac16,13": "MacBook Air 15″ (M4, 2025)",
        "MacBookPro17,1": "MacBook Pro 13″ (M1, 2020)",
        "MacBookPro18,1": "MacBook Pro 16″ (M1 Pro, 2021)",
        "MacBookPro18,2": "MacBook Pro 16″ (M1 Max, 2021)",
        "MacBookPro18,3": "MacBook Pro 14″ (M1 Pro, 2021)",
        "MacBookPro18,4": "MacBook Pro 14″ (M1 Max, 2021)",
        "Mac14,7": "MacBook Pro 13″ (M2, 2022)",
    ]
}

struct CPULoad {
    var total: Double
    var perCore: [Double]
}

/// CPU usage from the difference between two samples of per-core tick counters.
final class CPUSampler {
    private var previous: [[UInt32]] = []

    func sample() -> CPULoad {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else {
            return CPULoad(total: 0, perCore: [])
        }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        let current = (0..<Int(cpuCount)).map { core in
            (0..<states).map { UInt32(bitPattern: info[core * states + $0]) }
        }
        defer { previous = current }
        guard previous.count == current.count else {
            return CPULoad(total: 0, perCore: Array(repeating: 0, count: current.count))
        }

        var busy: UInt64 = 0, all: UInt64 = 0
        let perCore = zip(current, previous).map { now, before -> Double in
            let ticks = zip(now, before).map { UInt64($0 &- $1) }
            let total = ticks.reduce(0, +)
            let idle = ticks[Int(CPU_STATE_IDLE)]
            busy += total - idle
            all += total
            return total > 0 ? Double(total - idle) / Double(total) : 0
        }
        return CPULoad(total: all > 0 ? Double(busy) / Double(all) : 0, perCore: perCore)
    }
}

/// Finds the processes using the most CPU between two samples.
final class ProcessSampler {
    private var previousCPU: [pid_t: UInt64] = [:]
    private var previousTime: UInt64 = 0
    private var names: [pid_t: (name: String, isApp: Bool)] = [:]
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func sample(limit: Int = 5) -> [ProcessUsage] {
        let now = DispatchTime.now().uptimeNanoseconds
        let capacity = 8192
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride)))
        guard count > 0 else { return [] }

        let elapsed = previousTime > 0 ? Double(now - previousTime) : 0
        var cpuTimes: [pid_t: UInt64] = [:]
        var usage: [ProcessUsage] = []
        // Skip PowerDeck itself: a monitor shouldn't suggest quitting itself.
        let ownPID = getpid()
        for pid in pids.prefix(min(count, capacity)) where pid > 0 && pid != ownPID {
            guard let cpuTime = cpuNanoseconds(pid) else { continue }
            cpuTimes[pid] = cpuTime
            guard elapsed > 0, let before = previousCPU[pid], cpuTime >= before else { continue }
            let percent = Double(cpuTime - before) / elapsed * 100
            if percent >= 1 {
                let identity = identify(pid)
                usage.append(ProcessUsage(id: pid, name: identity.name, cpuPercent: percent, isApp: identity.isApp))
            }
        }
        previousCPU = cpuTimes
        previousTime = now
        names = names.filter { cpuTimes[$0.key] != nil }
        return Array(usage.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
    }

    private func cpuNanoseconds(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { return nil }
        // On Apple silicon these are Mach time units, not nanoseconds.
        return (info.ri_user_time + info.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    private func identify(_ pid: pid_t) -> (name: String, isApp: Bool) {
        if let cached = names[pid] { return cached }
        let app = NSRunningApplication(processIdentifier: pid)
        var resolved = app?.localizedName
        if resolved == nil {
            var buffer = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
                resolved = URL(fileURLWithPath: buffer.decodedString).lastPathComponent
            }
        }
        let identity = (name: resolved ?? "Process \(pid)", isApp: app?.activationPolicy == .regular)
        names[pid] = identity
        return identity
    }
}
