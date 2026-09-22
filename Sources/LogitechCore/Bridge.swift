import Foundation

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
    public struct Battery: Decodable, Sendable { public let percentage: Int? }
    public struct Capabilities: Decodable, Sendable { public let pointer: Bool? }
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
        guard inventoryHealth == "Ready", matches.count == 1, matches[0].online,
              matches[0].capabilities?.pointer == true else { throw BridgeProblem("That mouse is unavailable or ambiguous. Refresh and select it again.") }
        return matches[0]
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
    private let runner: any CommandRunner
    public init(runner: any CommandRunner = ProcessRunner()) { self.runner = runner }
    private func command<T: Decodable>(_ executable: URL, _ arguments: [String], as: T.Type) async throws -> T {
        let data = try await runner.run(executable, arguments: ["control"] + arguments)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw BridgeProblem("OpenLogi returned an unsupported response. Install a matching CLI and agent build (protocol 32).") }
    }
    public func inventory(_ exe: URL) async throws -> Inventory {
        let value = try await command(exe, ["devices"], as: Inventory.self)
        guard value.schemaVersion == 1, value.protocolVersion == 32 else { throw BridgeProblem("This module needs OpenLogi protocol 32. Update the CLI and agent together.") }
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
        _ = try await inventory(exe).target(id)
        let before = try await dpi(exe, id: id)
        guard before.capabilities.values.contains(value) else { throw BridgeProblem("That DPI is not supported by this mouse.") }
        let after = try validate(try await command(exe, ["dpi", "--device", id, "--set", String(value)], as: Setting<DPI>.self), id: id, written: true)
        guard after.current == value else { throw BridgeProblem("The DPI read-back differs. Refresh before trying again; no retry was sent.") }
        return after
    }
    public func setWheel(_ exe: URL, id: String, mode: String?, threshold: Int?) async throws -> Wheel {
        guard mode != nil || threshold != nil, mode == nil || ["free", "ratchet"].contains(mode!), threshold == nil || (1...255).contains(threshold!) else { throw BridgeProblem("Choose a valid wheel mode or sensitivity (1–255).") }
        _ = try await inventory(exe).target(id)
        var args = ["smartshift", "--device", id]
        if let mode { args += ["--mode", mode] }; if let threshold { args += ["--threshold", String(threshold)] }
        let after = try validate(try await command(exe, args, as: Setting<Wheel>.self), id: id, written: true)
        guard mode == nil || after.mode.lowercased() == mode, threshold == nil || after.autoDisengage == threshold else { throw BridgeProblem("The wheel read-back differs. Refresh before trying again; no retry was sent.") }
        return after
    }
}
