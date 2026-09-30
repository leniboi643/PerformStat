import Foundation
import AppKit
import ServiceManagement

/// Every user-configurable knob, persisted in standard UserDefaults.
struct StatFlags: OptionSet {
    let rawValue: Int
    static let cpu = StatFlags(rawValue: 1 << 0)
    static let gpu = StatFlags(rawValue: 1 << 1)
    static let memory = StatFlags(rawValue: 1 << 2)
    static let swap = StatFlags(rawValue: 1 << 3)
    static let disk = StatFlags(rawValue: 1 << 4)
    static let network = StatFlags(rawValue: 1 << 5)
    static let uptime = StatFlags(rawValue: 1 << 6)
    static let pressure = StatFlags(rawValue: 1 << 7)
    static let thermal = StatFlags(rawValue: 1 << 8)
    static let battery = StatFlags(rawValue: 1 << 9)
    static let system = StatFlags(rawValue: 1 << 10)

    static let all: StatFlags = [.cpu, .gpu, .memory, .swap, .disk, .network, .uptime,
                                 .pressure, .thermal, .battery, .system]
}

enum PositionPreset: String, CaseIterable {
    case topLeft, topCenter, topRight
    case middleLeft, middleRight
    case bottomLeft, bottomCenter, bottomRight
    case custom

    var label: String {
        switch self {
        case .topLeft: return "top left"
        case .topCenter: return "top center"
        case .topRight: return "top right"
        case .middleLeft: return "middle left"
        case .middleRight: return "middle right"
        case .bottomLeft: return "bottom left"
        case .bottomCenter: return "bottom center"
        case .bottomRight: return "bottom right"
        case .custom: return "custom…"
        }
    }
}

final class SettingsModel {
    static let shared = SettingsModel()

    private let d: UserDefaults

    // keys
    private enum K {
        static let visible = "overlayVisible"
        static let stats = "enabledStats"
        static let interval = "updateInterval"
        static let fontSize = "fontSize"
        static let opacity = "textOpacity"
        static let lineSpacing = "lineSpacing"
        static let position = "positionPreset"
        static let customX = "customX"
        static let customY = "customY"
        static let screenID = "preferredScreen"
        static let launchAtLogin = "launchAtLogin"
        static let fontName = "fontName"
    }

    init(defaults: UserDefaults = .standard) {
        d = defaults
        d.register(defaults: [
            K.visible: true,
            K.stats: StatFlags.all.rawValue,
            K.interval: 1.0,
            K.fontSize: 13.0,
            K.opacity: 0.9,
            K.lineSpacing: 3.0,
            K.position: PositionPreset.topLeft.rawValue,
            K.customX: 24.0,
            K.customY: 24.0,
            K.screenID: "main",
            K.launchAtLogin: false,
            K.fontName: "SFMono-Regular",
        ])
    }

    var isVisible: Bool {
        get { d.bool(forKey: K.visible) }
        set { d.set(newValue, forKey: K.visible) }
    }
    var enabledStats: StatFlags {
        get { StatFlags(rawValue: d.integer(forKey: K.stats)) }
        set { d.set(newValue.rawValue, forKey: K.stats) }
    }
    var updateInterval: Double {
        get { d.double(forKey: K.interval) }
        set { d.set(min(max(newValue, 0.25), 10), forKey: K.interval) }
    }
    var fontSize: Double {
        get { d.double(forKey: K.fontSize) }
        set { d.set(min(max(newValue, 9), 28), forKey: K.fontSize) }
    }
    var textOpacity: Double {
        get { d.double(forKey: K.opacity) }
        set { d.set(min(max(newValue, 0.2), 1.0), forKey: K.opacity) }
    }
    var lineSpacing: Double {
        get { d.double(forKey: K.lineSpacing) }
        set { d.set(min(max(newValue, 0), 12), forKey: K.lineSpacing) }
    }
    var position: PositionPreset {
        get { PositionPreset(rawValue: d.string(forKey: K.position) ?? "") ?? .topLeft }
        set { d.set(newValue.rawValue, forKey: K.position) }
    }
    var customX: Double {
        get { d.double(forKey: K.customX) }
        set { d.set(newValue, forKey: K.customX) }
    }
    var customY: Double {
        get { d.double(forKey: K.customY) }
        set { d.set(newValue, forKey: K.customY) }
    }
    var preferredScreen: String {
        get { d.string(forKey: K.screenID) ?? "main" }
        set { d.set(newValue, forKey: K.screenID) }
    }
    var fontName: String {
        get { d.string(forKey: K.fontName) ?? "SFMono-Regular" }
        set { d.set(newValue, forKey: K.fontName) }
    }

    var launchAtLogin: Bool {
        get { d.bool(forKey: K.launchAtLogin) }
        set {
            d.set(newValue, forKey: K.launchAtLogin)
            if #available(macOS 13.0, *) {
                let service = SMAppService.mainApp
                do {
                    if newValue { try service.register() } else { try service.unregister() }
                } catch {
                    NSLog("performstat: launch-at-login error: \(error.localizedDescription)")
                }
            }
        }
    }

    func reset() {
        for key in [K.visible, K.stats, K.interval, K.fontSize, K.opacity, K.lineSpacing,
                    K.position, K.customX, K.customY, K.screenID, K.launchAtLogin, K.fontName] {
            d.removeObject(forKey: key)
        }
        // re-register defaults and undo login item
        d.set(true, forKey: K.visible)
        d.set(StatFlags.all.rawValue, forKey: K.stats)
        if launchAtLogin { launchAtLogin = false }
    }
}
