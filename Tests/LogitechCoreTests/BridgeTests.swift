import XCTest
@testable import LogitechCore

private actor ScriptedRunner: CommandRunner {
    var replies: [Result<Data, Error>]
    var calls: [[String]] = []
    init(_ strings: [String]) { replies = strings.map { .success(Data($0.utf8)) } }
    func run(_ executable: URL, arguments: [String]) async throws -> Data {
        calls.append(arguments)
        guard !replies.isEmpty else { throw BridgeProblem("Unexpected extra request") }
        return try replies.removeFirst().get()
    }
}
final class BridgeTests: XCTestCase {
    let exe = URL(fileURLWithPath: "/fixture/OpenLogi.app/Contents/MacOS/openlogi")
    let id = "direct 046d:b034"
    var inventory: String { #"{"schema_version":1,"protocol_version":32,"agent_version":"fixture","inventory_health":"Ready","devices":[{"id":"direct 046d:b034","name":"Fixture Mouse","online":true,"battery":{"percentage":35},"capabilities":{"pointer":true}}]}"# }
    func dpi(_ value: Int, written: Bool = false) -> String { "{\"schema_version\":1,\"device\":\"\(id)\",\"written\":\(written),\"current\":{\"current\":\(value),\"capabilities\":{\"values\":[800,1600,2000]}}}" }
    func testReadOnlyInventoryAndSettingsNeverIncludeWriteArguments() async throws {
        let runner = ScriptedRunner([inventory, dpi(2000)])
        let bridge = LogitechBridge(runner: runner)
        let found = try await bridge.inventory(exe)
        XCTAssertEqual(found.mice.first?.battery?.percentage, 35)
        let value = try await bridge.dpi(exe, id: id)
        XCTAssertEqual(value.current, 2000)
        let calls = await runner.calls
        XCTAssertEqual(calls, [["control", "devices"], ["control", "dpi", "--device", id]])
    }
    func testProtocolMismatchAndOfflineTargetBlockWrites() async {
        for data in [inventory.replacingOccurrences(of: ":32", with: ":31"), inventory.replacingOccurrences(of: "\"online\":true", with: "\"online\":false")] {
            let runner = ScriptedRunner([data]); let bridge = LogitechBridge(runner: runner)
            do { _ = try await bridge.setDPI(exe, id: id, value: 1600); XCTFail("must reject") } catch {}
            let calls = await runner.calls; XCTAssertEqual(calls.count, 1)
        }
    }
    func testUnsupportedDPIAndReadbackMismatchDoNotRetry() async {
        for value in [900,1600] {
            let runner = ScriptedRunner([inventory, dpi(2000), dpi(2000, written: true)])
            let bridge = LogitechBridge(runner: runner)
            do { _ = try await bridge.setDPI(exe, id: id, value: value); XCTFail("must reject") } catch {}
            let calls = await runner.calls; XCTAssertEqual(calls.count, value == 900 ? 2 : 3)
        }
    }
    func testSuccessfulWriteRequiresExactDeviceAndReadback() async throws {
        let runner = ScriptedRunner([inventory, dpi(2000), dpi(1600, written: true)])
        let value = try await LogitechBridge(runner: runner).setDPI(exe, id: id, value: 1600)
        XCTAssertEqual(value.current,1600)
        let calls = await runner.calls
        XCTAssertEqual(calls.last, ["control","dpi","--device",id,"--set","1600"])
    }
    func testPartialWheelDoesNotResendUnspecifiedFields() async throws {
        let reply = "{\"schema_version\":1,\"device\":\"\(id)\",\"written\":true,\"current\":{\"mode\":\"Free\",\"auto_disengage\":60,\"tunable_torque\":80}}"
        let runner = ScriptedRunner([inventory,reply])
        let wheel = try await LogitechBridge(runner: runner).setWheel(exe, id:id,mode:"free",threshold:nil)
        XCTAssertEqual(wheel.tunableTorque,80)
        let calls = await runner.calls; XCTAssertEqual(calls.last,["control","smartshift","--device",id,"--mode","free"])
    }
    func testWrongResponseDeviceAndAmbiguousInventoryAreRejected() async {
        let wrong = dpi(1600,written:true).replacingOccurrences(of:id,with:"other")
        let runner = ScriptedRunner([inventory,dpi(2000),wrong])
        do { _ = try await LogitechBridge(runner:runner).setDPI(exe,id:id,value:1600); XCTFail("wrong target") } catch {}
        let duplicate = inventory.replacingOccurrences(of:"]}",with:", {\"id\":\"direct 046d:b034\",\"name\":\"Other\",\"online\":true,\"capabilities\":{\"pointer\":true}}]}")
        let other = ScriptedRunner([duplicate])
        do { _ = try await LogitechBridge(runner:other).setDPI(exe,id:id,value:1600); XCTFail("ambiguous target") } catch {}
        let calls = await other.calls; XCTAssertEqual(calls.count,1)
    }
    func testRunnerFailureAdviceDistinguishesReadsFromWrites() {
        XCTAssertTrue(ProcessRunner.failureAdvice(arguments: ["control", "dpi", "--device", id]).contains("read-only"))
        for option in ["--set", "--mode", "--threshold"] {
            XCTAssertTrue(ProcessRunner.failureAdvice(arguments: ["control", "dpi", option, "1"]).contains("may have taken effect"))
        }
    }
    func testRunnerPassesTextLiterallyWithoutShell() async throws {
        let text = "$(touch /tmp/not-a-command); literal"
        let result = try await ProcessRunner().run(URL(fileURLWithPath:"/usr/bin/printf"),arguments:["%s",text])
        XCTAssertEqual(String(data:result,encoding:.utf8),text)
    }
}
