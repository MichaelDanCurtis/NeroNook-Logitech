import Foundation

/// Compare only fresh, healthy observations of one explicitly selected keyboard.
/// Initial state, service failures, sleep and target changes are baselines, not events.
public struct KeyboardEventTracker: Sendable {
    public struct Event: Equatable, Sendable {
        public let id: UUID
        public let device: String
        public let kind: String
        public let connected: Bool
        public let battery: Int?
        public let observedAt: Date
        public var message: String {
            switch kind {
            case "connected": return "Keyboard connected"
            case "disconnected": return "Keyboard disconnected"
            case "low_battery": return "Keyboard battery reached \(battery ?? 0)%"
            default: return "Keyboard battery recovered to \(battery ?? 0)%"
            }
        }
    }
    private struct State: Sendable {
        var device: String
        var online: Bool
        var low: Bool?
        var observedAt: Date
        var threshold: Int
    }
    private var previous: State?
    public init() {}
    public mutating func reset() { previous = nil }
    public mutating func observe(_ inventory: Inventory, selected: String, threshold: Int,
                                 enabled: Bool, at date: Date = Date()) -> [Event] {
        guard enabled, inventory.inventoryHealth == "Ready", !selected.isEmpty,
              (1...50).contains(threshold), date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 >= 0 else {
            reset(); return []
        }
        let matches = inventory.devices.filter { $0.id == selected }
        guard matches.count <= 1, matches.first?.isKeyboard != false else { reset(); return [] }
        // A remembered keyboard may disappear from a healthy inventory. A new
        // missing identity cannot establish that it was ever connected.
        guard matches.first != nil || previous?.device == selected else { reset(); return [] }
        let current = matches.first
        let online = current?.online == true
        let battery = online ? current?.battery?.percentage.flatMap { (0...100).contains($0) ? $0 : nil } : nil
        let old = previous
        if let old, old.device == selected, date <= old.observedAt { return [] }
        let continuous = old.map { $0.device == selected && $0.threshold == threshold && date.timeIntervalSince($0.observedAt) <= 20 } ?? false
        let low: Bool? = battery.map { value in
            continuous && old?.low == true ? value < min(100, threshold + 5) : value <= threshold
        }
        previous = .init(device: selected, online: online, low: low, observedAt: date, threshold: threshold)
        guard continuous, let old else { return [] }
        var kinds: [String] = []
        if old.online != online { kinds.append(online ? "connected" : "disconnected") }
        if old.online && online, let wasLow = old.low, let isLow = low, wasLow != isLow {
            kinds.append(isLow ? "low_battery" : "battery_recovered")
        }
        return kinds.map { .init(id: UUID(), device: selected, kind: $0, connected: online, battery: battery, observedAt: date) }
    }
}
