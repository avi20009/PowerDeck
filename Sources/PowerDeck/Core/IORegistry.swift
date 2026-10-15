import Foundation
import IOKit

/// Thin helpers over the IOKit registry, where macOS publishes battery, charger, port and USB state.
enum IORegistry {
    /// Every registered service of `className` (or a subclass). Callers own the returned handles.
    static func services(_ className: String) -> [io_service_t] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var result: [io_service_t] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            result.append(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    static func properties(of entry: io_registry_entry_t) -> [String: Any] {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        return dict
    }

    /// Property dictionaries for every service of `className`.
    static func allProperties(_ className: String) -> [[String: Any]] {
        services(className).map { service in
            defer { IOObjectRelease(service) }
            return properties(of: service)
        }
    }

    /// The first value of `key` found on `entry` or one of its ancestors in the service plane.
    static func ancestorValue(_ key: String, from entry: io_registry_entry_t, maxDepth: Int = 12) -> Any? {
        var current = entry
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<maxDepth {
            if let value = IORegistryEntryCreateCFProperty(current, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                return value
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(current)
            current = parent
        }
        return nil
    }
}

/// Typed access to registry property dictionaries.
extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int? {
        (self[key] as? NSNumber).map { Int(truncatingIfNeeded: $0.int64Value) }
    }

    func double(_ key: String) -> Double? {
        (self[key] as? NSNumber)?.doubleValue
    }

    func bool(_ key: String) -> Bool? {
        (self[key] as? NSNumber)?.boolValue
    }

    func string(_ key: String) -> String? {
        if let string = self[key] as? String { return string.isEmpty ? nil : string }
        if let data = self[key] as? Data {
            let text = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    func dict(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func dicts(_ key: String) -> [[String: Any]] {
        self[key] as? [[String: Any]] ?? []
    }

    func strings(_ key: String) -> [String] {
        self[key] as? [String] ?? []
    }
}

enum Sysctl {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.decodedString
    }

    static func integer<T: FixedWidthInteger>(_ name: String, as type: T.Type = T.self) -> T? {
        var value = T.zero
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}

extension Array where Element == CChar {
    /// The NUL-terminated C string held in this buffer.
    var decodedString: String {
        String(decoding: prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
