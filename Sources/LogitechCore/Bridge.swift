import Foundation
import CryptoKit

public struct BridgeProblem: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public struct Device: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let online: Bool
    public let battery: Battery?
    public let capabilities: Capabilities?
    public var isPointer: Bool { capabilities?.pointer == true }
    public var isKeyboard: Bool { capabilities?.pointer == false && capabilities?.buttons == true }
    public var selectionAction: String { "device_" + SHA256.hash(data: Data(id.utf8)).prefix(28).map { String(format: "%02x", $0) }.joined() }
    public struct Battery: Decodable, Sendable { public let percentage: Int?; public let status: String? }
    public struct Capabilities: Decodable, Sendable { public let pointer: Bool?; public let buttons: Bool? }
}
public struct Inventory: Decodable, Sendable {
    public let schemaVersion: Int
    public let protocolVersion: Int
    public let agentVersion: String
    public let inventoryHealth: String
    public let devices: [Device]
    public var mice: [Device] { devices.filter { $0.capabilities?.pointer == true } }
    public func target(_ id: String) throws -> Device {
        let matches = devices.filter { $0.id == id }
        guard inventoryHealth == "Ready", matches.count == 1, matches[0].online else { throw BridgeProblem("That device is unavailable or ambiguous. Refresh and select it again.") }
        return matches[0]
    }
    public func pointerTarget(_ id: String) throws -> Device {
        let device = try target(id)
        guard device.isPointer else { throw BridgeProblem("This setting requires a mouse. No change was attempted.") }
        return device
    }
}
public struct DPI: Decodable, Sendable {
    public let current: Int
    public let capabilities: Values
    public struct Values: Decodable, Sendable { public let values: [Int] }
}
public struct Wheel: Decodable, Sendable {
    public let mode: String
    public let autoDisengage: Int
    public let tunableTorque: Int?
}
public struct Setting<T: Decodable & Sendable>: Decodable, Sendable {
    public let schemaVersion: Int
    public let device: String
    public let written: Bool
    public let current: T
}
public protocol CommandRunner: Sendable {
    func run(_ executable: URL, arguments: [String]) async throws -> Data
}
public actor LogitechBridge {
    public enum Format: Equatable, Sendable { case legacy, api, automatic }
    private let runner: any CommandRunner
    private let format: Format
    private var formats: [String: Format] = [:]
    public init(runner: any CommandRunner = ProcessRunner(), format: Format = .legacy) { self.runner = runner; self.format = format }
    private func connectionFormat(_ exe: URL) async throws -> Format {
        if format != .automatic { return format }
        let stamp = (try? exe.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = exe.path + "|" + String(stamp)
        if let cached = formats[key] { return cached }
        let help = String(decoding: try await runner.run(exe, arguments: ["--help"]), as: UTF8.self)
        let found: Format = help.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("api ") }) ? .api : .legacy
        formats = [key: found]; return found
    }
    public func supportsHostSwitch(_ exe: URL) async throws -> Bool {
        guard try await connectionFormat(exe) == .api else { return false }
        let help = String(decoding: try await runner.run(exe, arguments: ["api", "--help"]), as: UTF8.self)
        return help.contains("host-switch-events") && help.contains("watch-host-switch")
    }
    public func setHostSwitchEvents(_ exe: URL, id: String, enabled: Bool) async throws {
        let found = try await inventory(exe)
        let matches = found.devices.filter { $0.id == id }
        guard matches.count == 1, matches[0].isKeyboard, !enabled || matches[0].online, try await supportsHostSwitch(exe) else { throw BridgeProblem("This OpenLogi connection cannot publish Easy-Switch choices yet.") }
        let bytes = try await runner.run(exe, arguments: ["api", "--save", "host-switch-events", "--device", id, "--set", enabled ? "on" : "off"])
        guard let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], envelope["schema_version"] as? Int == 1, envelope["ok"] as? Bool == true,
              let data = envelope["data"] as? [String: Any], data["device"] as? String == id, data["host_switch_events"] as? Bool == enabled, data["persistence"] as? String == "saved" else {
            throw BridgeProblem("OpenLogi did not confirm saving its host-button watch. No retry was sent.")
        }
    }
    private func command<T: Decodable>(_ executable: URL, _ arguments: [String], as: T.Type) async throws -> T {
        let mode = try await connectionFormat(executable)
        let translated = mode == .api ? arguments.map { $0 == "--threshold" ? "--auto-disengage" : $0 } : arguments
        let bytes = try await runner.run(executable, arguments: [mode == .api ? "api" : "control"] + translated)
        let data: Data
        if mode == .api {
            guard let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], envelope["schema_version"] as? Int == 1, envelope["ok"] as? Bool == true,
                  let result = envelope["data"] as? [String: Any] else { throw BridgeProblem("OpenLogi API did not return a supported successful response. No retry was sent.") }
            var normalized: [String: Any]
            if arguments.first == "devices" {
                guard let health = result["inventory"] as? String, ["ready", "scanning", "unavailable"].contains(health) else { throw BridgeProblem("OpenLogi returned an unknown inventory state.") }
                normalized = ["schema_version":1,"protocol_version":0,"agent_version":"matched by OpenLogi API","inventory_health":health.capitalized,"devices":result["devices"] ?? []]
            } else {
                let current: [String: Any]
                if arguments.first == "dpi" { current = ["current":result["current"] ?? NSNull(),"capabilities":["values":result["supported"] ?? []]] }
                else { current = ["mode":result["mode"] ?? NSNull(),"auto_disengage":result["auto_disengage"] ?? NSNull(),"tunable_torque":result["tunable_torque"] ?? NSNull()] }
                normalized = ["schema_version":1,"device":result["device"] ?? NSNull(),"written":arguments.contains("--set") || arguments.contains("--mode") || arguments.contains("--threshold"),"current":current]
            }
            data = try JSONSerialization.data(withJSONObject: normalized)
        } else { data = bytes }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw BridgeProblem("OpenLogi returned an unsupported response. Install a matching CLI and agent build (protocol 32).") }
    }
    public func inventory(_ exe: URL) async throws -> Inventory {
        let value = try await command(exe, ["devices"], as: Inventory.self)
        guard value.schemaVersion == 1, value.protocolVersion == (try await connectionFormat(exe) == .api ? 0 : 32) else { throw BridgeProblem("This module needs OpenLogi protocol 32. Update the CLI and agent together.") }
        return value
    }
    private func validate<T>(_ value: Setting<T>, id: String, written: Bool) throws -> T {
        guard value.schemaVersion == 1, value.device == id, value.written == written else { throw BridgeProblem("OpenLogi could not confirm the requested mouse and operation.") }
        return value.current
    }
    public func dpi(_ exe: URL, id: String) async throws -> DPI {
        try validate(try await command(exe, ["dpi", "--device", id], as: Setting<DPI>.self), id: id, written: false)
    }
    public func wheel(_ exe: URL, id: String) async throws -> Wheel {
        try validate(try await command(exe, ["smartshift", "--device", id], as: Setting<Wheel>.self), id: id, written: false)
    }
    public func setDPI(_ exe: URL, id: String, value: Int) async throws -> DPI {
        _ = try await inventory(exe).pointerTarget(id)
        let before = try await dpi(exe, id: id)
        guard before.capabilities.values.contains(value) else { throw BridgeProblem("That DPI is not supported by this mouse.") }
        let after = try validate(try await command(exe, ["dpi", "--device", id, "--set", String(value)], as: Setting<DPI>.self), id: id, written: true)
        guard after.current == value else { throw BridgeProblem("The DPI read-back differs. Refresh before trying again; no retry was sent.") }
        return after
    }
    public func setWheel(_ exe: URL, id: String, mode: String?, threshold: Int?) async throws -> Wheel {
        guard mode != nil || threshold != nil, mode == nil || ["free", "ratchet"].contains(mode!), threshold == nil || (1...255).contains(threshold!) else { throw BridgeProblem("Choose a valid wheel mode or sensitivity (1–255).") }
        _ = try await inventory(exe).pointerTarget(id)
        var args = ["smartshift", "--device", id]
        if let mode { args += ["--mode", mode] }; if let threshold { args += ["--threshold", String(threshold)] }
        let after = try validate(try await command(exe, args, as: Setting<Wheel>.self), id: id, written: true)
        guard mode == nil || after.mode.lowercased() == mode, threshold == nil || after.autoDisengage == threshold else { throw BridgeProblem("The wheel read-back differs. Refresh before trying again; no retry was sent.") }
        return after
    }
}
