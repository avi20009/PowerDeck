import Foundation

/// Reads the physical ports (USB-C, MagSafe) from the AppleHPMInterface services, plus the
/// USB Power Delivery state macOS attaches to each one.
enum PortReader {
    static func read(outputs: [PortPowerOut], onExternalPower: Bool) -> [PortInfo] {
        // A PD partner (SOP) only exists while a Power Delivery device is plugged in; without
        // one, the port's SOPMfgString is left over from an earlier connection.
        let partners = Dictionary(
            IORegistry.allProperties("IOPortTransportComponentCCUSBPDSOP").compactMap { props in
                portKey(props).map { ($0, props) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let chargingPorts = Set(
            IORegistry.allProperties("IOPortFeaturePowerSource")
                .filter { $0["WinningPowerSourceOption"] != nil }
                .compactMap(portKey)
        )

        return IORegistry.allProperties("AppleHPMInterface").compactMap { props -> PortInfo? in
            guard let id = props.string("PortDescription") ?? props.string("Description") else { return nil }
            let kind = props.string("PortTypeDescription") ?? "USB-C"
            let number = id.split(separator: "@").last.flatMap { Int($0) } ?? 0
            let key = "\(kind)@\(number)"
            let partner = partners[key]
            let partnerName = partner == nil ? nil : props.string("SOPMfgString")
            return PortInfo(
                id: id,
                kind: kind,
                number: number,
                isConnected: props.bool("ConnectionActive") ?? false,
                activeTransports: props.strings("TransportsActive"),
                supportedTransports: props.strings("TransportsSupported"),
                partnerName: partnerName,
                partnerBrand: partner?.int("Vendor ID").flatMap(Vendors.name(for:)) ?? partnerName.flatMap(Vendors.brand(forModel:)),
                overcurrentCount: props.int("Overcurrent Count") ?? 0,
                isChargingMac: onExternalPower && chargingPorts.contains(key),
                powerOut: kind == "USB-C" ? outputs.first { $0.portIndex == number } : nil
            )
        }
        .sorted { ($0.isMagSafe ? 1 : 0, $0.number) < ($1.isMagSafe ? 1 : 0, $1.number) }
    }

    private static func portKey(_ props: [String: Any]) -> String? {
        guard let kind = props.string("ParentPortTypeDescription"),
              let number = props.int("ParentPortNumber") else { return nil }
        return "\(kind)@\(number)"
    }
}
