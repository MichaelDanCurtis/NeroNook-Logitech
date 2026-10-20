import Foundation

public struct HostSwitchChoice: Equatable, Sendable {
    public let device: String
    public let channel: Int
    public let observedAt: Double
    public let sequence: UInt64
    public init(line: Data, expectedDevice: String, after sequence: UInt64, now: Double) throws {
        guard line.count <= 16384, let envelope = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              envelope["schema_version"] as? Int == 1, envelope["ok"] as? Bool == true,
              let data = envelope["data"] as? [String: Any], data["type"] as? String == "host_switch",
              let device = data["device"] as? String, device == expectedDevice,
              let n = data["channel"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.rounded() == n.doubleValue, (1...3).contains(n.intValue),
              let stamp = data["observed_at_ms"] as? NSNumber, CFGetTypeID(stamp) != CFBooleanGetTypeID(),
              let seq = data["sequence"] as? NSNumber, CFGetTypeID(seq) != CFBooleanGetTypeID(), seq.doubleValue.isFinite, seq.doubleValue >= 1, seq.doubleValue <= 9007199254740991, seq.doubleValue.rounded() == seq.doubleValue, seq.uint64Value > sequence,
              now.isFinite, stamp.doubleValue.isFinite, stamp.doubleValue / 1000 <= now + 0.25, now - stamp.doubleValue / 1000 <= 2 else { throw BridgeProblem("Stale or invalid keyboard host choice.") }
        self.device = device; self.channel = n.intValue; self.observedAt = stamp.doubleValue / 1000; self.sequence = seq.uint64Value
    }
}
