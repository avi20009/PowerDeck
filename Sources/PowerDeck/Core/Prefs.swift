import Foundation

/// UserDefaults keys shared by the settings window and the monitor.
enum Prefs {
    static let menuBarStyle = "menuBarStyle"
    static let refreshInterval = "refreshInterval"
    static let notifyDevices = "notifyDevices"
    static let showInDock = "showInDock"

    static var interval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: refreshInterval)
        return value > 0 ? value : 2
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case power, battery, macLoad, iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .power: "Power coming in"
        case .battery: "Battery percentage"
        case .macLoad: "Power your Mac is using"
        case .iconOnly: "Icon only"
        }
    }
}
