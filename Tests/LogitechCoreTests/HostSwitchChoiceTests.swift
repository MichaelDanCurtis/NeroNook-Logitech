import XCTest
@testable import LogitechCore

final class HostSwitchChoiceTests: XCTestCase {
    private func line(_ overrides: [String: Any] = [:]) throws -> Data {
        var body: [String: Any] = ["type":"host_switch","device":"fixture-keyboard","sequence":7,"channel":2,"observed_at_ms":101000]
        overrides.forEach { body[$0.key] = $0.value }
        return try JSONSerialization.data(withJSONObject: ["schema_version":1,"ok":true,"data":body])
    }
    func testFreshExactChoicesAndInvalidInputs() throws {
        let event = try HostSwitchChoice(line: line(), expectedDevice: "fixture-keyboard", after: 6, now: 101.5)
        XCTAssertEqual(event.channel, 2); XCTAssertEqual(event.sequence, 7); XCTAssertEqual(event.observedAt, 101)
        for invalid: [String: Any] in [["channel":true],["channel":1.5],["channel":4],["device":"other"],["sequence":6],["sequence":-1],["observed_at_ms":99000],["observed_at_ms":103000]] {
            XCTAssertThrowsError(try HostSwitchChoice(line: line(invalid), expectedDevice: "fixture-keyboard", after: 6, now: 101.5))
        }
        XCTAssertThrowsError(try HostSwitchChoice(line: line(), expectedDevice: "fixture-keyboard", after: 7, now: 101.5))
    }
}

private actor APIResponses: CommandRunner {
    var requests: [[String]] = []
    func run(_ executable: URL, arguments: [String]) async throws -> Data {
        requests.append(arguments)
        let payload: [String: Any]
        if arguments == ["api", "devices"] {
            payload = ["inventory":"ready","devices":[["id":"fixture-keyboard","name":"Fixture keys","online":true,"capabilities":["pointer":false,"buttons":true]]]]
        } else if arguments == ["api", "--help"] { return Data("host-switch-events watch-host-switch".utf8) }
        else if arguments == ["api", "--save", "host-switch-events", "--device", "fixture-keyboard", "--set", "on"] {
            payload = ["device":"fixture-keyboard","host_switch_events":true,"persistence":"saved"]
        } else { throw BridgeProblem("Unexpected command") }
        return try JSONSerialization.data(withJSONObject: ["schema_version":1,"ok":true,"data":payload])
    }
    func recorded() -> [[String]] { requests }
}
final class ModernAPIHostTests: XCTestCase {
    func testAPIInventoryAndExactExplicitWatchConfiguration() async throws {
        let runner = APIResponses(), bridge = LogitechBridge(runner: runner, format: .api)
        let exe = URL(fileURLWithPath: "/fixture/openlogi")
        let inventory = try await bridge.inventory(exe)
        XCTAssertEqual(inventory.protocolVersion, 0)
        XCTAssertEqual(inventory.inventoryHealth, "Ready")
        XCTAssertTrue(try inventory.target("fixture-keyboard").isKeyboard)
        try await bridge.setHostSwitchEvents(exe, id: "fixture-keyboard", enabled: true)
        let calls = await runner.recorded()
        XCTAssertEqual(calls.filter { $0.contains("--save") }.count, 1)
        XCTAssertTrue(calls.allSatisfy { $0.first == "api" })
        do { try await bridge.setHostSwitchEvents(exe, id: "other", enabled: true); XCTFail("A different target was allowed") } catch {}
        let after = await runner.recorded()
        XCTAssertEqual(after.filter { $0.contains("--save") }.count, 1)
    }
}
