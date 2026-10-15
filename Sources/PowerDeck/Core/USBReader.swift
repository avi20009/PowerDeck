import Foundation
import IOKit

/// Enumerates USB devices and works out which physical port each one is plugged into.
enum USBReader {
    static func read() -> [USBDevice] {
        IORegistry.services("IOUSBHostDevice").compactMap { service -> USBDevice? in
            defer { IOObjectRelease(service) }
            let props = IORegistry.properties(of: service)
            let vendorID = props.int("idVendor") ?? 0
            let productID = props.int("idProduct") ?? 0
            let name = (props.string("USB Product Name") ?? props.string("kUSBProductString") ?? "USB device")
                .trimmingCharacters(in: .whitespaces)
            let vendor = props.string("USB Vendor Name") ?? props.string("kUSBVendorString")
                ?? Vendors.name(for: vendorID) ?? "Unknown maker"
            // The controller port a device hangs off records which physical port it is wired to,
            // e.g. "…/Port-USB-C@1". Devices behind a hub inherit it from further up.
            let portPath = IORegistry.ancestorValue("UsbIOPort", from: service) as? String
            return USBDevice(
                id: "\(props.int("locationID") ?? 0)-\(vendorID)-\(productID)",
                name: name,
                vendor: vendor,
                vendorID: vendorID,
                productID: productID,
                linkSpeed: props.int("UsbLinkSpeed") ?? linkSpeed(forDeviceSpeed: props.int("Device Speed")),
                portID: portPath?.split(separator: "/").last.map(String.init),
                kind: classify(name: name, vendorID: vendorID, deviceClass: props.int("bDeviceClass") ?? 0)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func linkSpeed(forDeviceSpeed speed: Int?) -> Int {
        switch speed {
        case 0: 1_500_000
        case 1: 12_000_000
        case 2: 480_000_000
        case 3: 5_000_000_000
        case 4: 10_000_000_000
        case 5: 20_000_000_000
        default: 0
        }
    }

    static func classify(name: String, vendorID: Int, deviceClass: Int) -> DeviceKind {
        let lowered = name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { lowered.contains($0) } }

        if vendorID == Vendors.apple {
            if has("iphone") { return .iPhone }
            if has("ipad") { return .iPad }
            if has("watch") { return .watch }
        }
        if has("charger", "charging", "cradle") { return .charger }
        if deviceClass == 9 || has("hub") { return .hub }
        if has("ssd", "disk", "drive", "flash", "storage", "card reader") { return .storage }
        if Vendors.phoneMakers.contains(vendorID) || has("android", "galaxy", "pixel") { return .phone }
        if has("keyboard") { return .keyboard }
        if has("mouse", "trackpad", "trackball") { return .mouse }
        if has("headset", "headphone", "speaker", "audio", "microphone", "airpods") { return .audio }
        if has("camera", "webcam") { return .camera }
        if has("display", "monitor") { return .display }
        if has("gamepad", "game controller", "dualsense", "dualshock", "xbox") { return .gameController }
        if Vendors.storageMakers.contains(vendorID) { return .storage }
        if Vendors.wearableMakers.contains(vendorID) { return .wearable }
        return .other
    }
}

/// USB-IF vendor IDs for makers the dashboard names or classifies.
enum Vendors {
    static let apple = 0x05AC
    static let phoneMakers: Set<Int> = [0x04E8, 0x18D1, 0x2717, 0x2A70, 0x12D1, 0x22B8, 0x22D9, 0x2D95, 0x1004, 0x0FCE]
    static let storageMakers: Set<Int> = [0x0781, 0x1058, 0x0BC2, 0x0951, 0x174C, 0x152D]
    static let wearableMakers: Set<Int> = [0x3695, 0x091E, 0x2687]

    static func name(for id: Int) -> String? { names[id] }

    /// Some chargers don't report a vendor ID; their model number often gives the maker away.
    static func brand(forModel model: String) -> String? {
        model.hasPrefix("ADLX") ? "Lenovo" : nil
    }

    private static let names: [Int: String] = [
        0x05AC: "Apple", 0x17EF: "Lenovo", 0x04E8: "Samsung", 0x18D1: "Google", 0x291A: "Anker",
        0x050D: "Belkin", 0x413C: "Dell", 0x03F0: "HP", 0x045E: "Microsoft", 0x054C: "Sony",
        0x0FCE: "Sony", 0x2717: "Xiaomi", 0x2A70: "OnePlus", 0x12D1: "Huawei", 0x22B8: "Motorola",
        0x22D9: "OPPO", 0x2D95: "vivo", 0x1004: "LG", 0x046D: "Logitech", 0x0781: "SanDisk",
        0x1058: "Western Digital", 0x0BC2: "Seagate", 0x0951: "Kingston", 0x0BDA: "Realtek",
        0x2109: "VIA Labs", 0x0B05: "ASUS", 0x091E: "Garmin", 0x3695: "WHOOP", 0x2687: "Fitbit",
        0x1532: "Razer", 0x174C: "ASMedia", 0x152D: "JMicron",
    ]
}
