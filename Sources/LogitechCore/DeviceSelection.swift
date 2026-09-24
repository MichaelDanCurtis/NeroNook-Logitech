import Foundation

public enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case mouse, keyboard
    public var title: String { self == .mouse ? "Mouse" : "Keyboard" }
    public func matches(_ device: Device) -> Bool { self == .mouse ? device.isPointer : device.isKeyboard }
}

/// Each tab owns an exact target. A missing remembered device never selects a replacement.
public struct DeviceSelection: Codable, Sendable {
    public var application = "/Applications/OpenLogi.app"
    public var device = "" // Retained for migration and the existing status action.
    public var mouse = ""
    public var keyboard = ""
    public var tab: DeviceKind = .mouse
    public init() {}
    private enum CodingKeys: String, CodingKey { case application, device, mouse, keyboard, tab }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        application = try c.decodeIfPresent(String.self, forKey: .application) ?? application
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? ""
        mouse = try c.decodeIfPresent(String.self, forKey: .mouse) ?? ""
        keyboard = try c.decodeIfPresent(String.self, forKey: .keyboard) ?? ""
        tab = try c.decodeIfPresent(DeviceKind.self, forKey: .tab) ?? .mouse
    }
    public func id(for kind: DeviceKind) -> String { kind == .mouse ? mouse : keyboard }
    public mutating func select(_ id: String, kind: DeviceKind, inventory: Inventory) throws {
        let matches = inventory.devices.filter { $0.id == id && kind.matches($0) }
        guard matches.count == 1 else { throw BridgeProblem("Choose an exact \(kind.rawValue) from this tab.") }
        if kind == .mouse { mouse = id } else { keyboard = id }
        device = id; tab = kind
    }
    public mutating func discover(in inventory: Inventory) {
        guard inventory.inventoryHealth == "Ready" else { return }
        for kind in DeviceKind.allCases where id(for: kind).isEmpty {
            let candidates = inventory.devices.filter { kind.matches($0) }
            // Preserve a legacy selection when it can be identified; never guess its kind.
            if let legacy = candidates.first(where: { $0.id == device }) {
                if kind == .mouse { mouse = legacy.id } else { keyboard = legacy.id }
                tab = kind
            } else if device.isEmpty || inventory.devices.contains(where: { $0.id == device }) {
                let online = candidates.filter(\.online)
                if online.count == 1 {
                    if kind == .mouse { mouse = online[0].id } else { keyboard = online[0].id }
                }
            }
        }
        if device.isEmpty { device = id(for: tab) }
    }
    public func validateTarget(_ id: String, kind: DeviceKind, inventory: Inventory?) throws {
        guard !id.isEmpty, id == self.id(for: kind), let inventory,
              kind.matches(try inventory.target(id)) else {
            throw BridgeProblem("The device changed or disconnected. Review this tab before applying.")
        }
    }
}
