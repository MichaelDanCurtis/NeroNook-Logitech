import XCTest
@testable import LogitechCore

final class DeviceSelectionTests: XCTestCase {
    func inventory(_ devices: String, health: String = "Ready") throws -> Inventory {
        let data = Data("{\"schema_version\":1,\"protocol_version\":32,\"agent_version\":\"fixture\",\"inventory_health\":\"\(health)\",\"devices\":[\(devices)]}".utf8)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Inventory.self, from: data)
    }
    let mouse = #"{"id":"mouse-a","name":"MX Master 3S","online":true,"capabilities":{"pointer":true}}"#
    let keyboard = #"{"id":"keyboard-a","name":"MX Keys S for Mac","online":true,"capabilities":{"pointer":false,"buttons":true}}"#
    func testMigratesLegacyKeyboardWithoutLosingIndependentMouse() throws {
        var preferences = try JSONDecoder().decode(DeviceSelection.self, from: Data(#"{"application":"/fixture/OpenLogi.app","device":"keyboard-a"}"#.utf8))
        preferences.discover(in: try inventory(mouse + "," + keyboard))
        XCTAssertEqual(preferences.keyboard, "keyboard-a"); XCTAssertEqual(preferences.mouse, "mouse-a")
        XCTAssertEqual(preferences.tab, .keyboard); XCTAssertEqual(preferences.application, "/fixture/OpenLogi.app")
        let reopened = try JSONDecoder().decode(DeviceSelection.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(reopened.keyboard, preferences.keyboard); XCTAssertEqual(reopened.mouse, preferences.mouse)
    }
    func testMissingRememberedMouseDoesNotSelectReplacement() throws {
        var preferences = DeviceSelection(); preferences.mouse = "missing"
        preferences.discover(in: try inventory(mouse + "," + keyboard))
        XCTAssertEqual(preferences.mouse, "missing"); XCTAssertEqual(preferences.keyboard, "keyboard-a")
        XCTAssertThrowsError(try preferences.validateTarget("mouse-a", kind: .mouse, inventory: inventory(mouse)))
    }
    func testTabChoiceAndStaleEventsNeverRetargetOtherKind() throws {
        var preferences = DeviceSelection(); let all = try inventory(mouse + "," + keyboard)
        preferences.discover(in: all)
        XCTAssertThrowsError(try preferences.select("keyboard-a", kind: .mouse, inventory: all))
        try preferences.select("keyboard-a", kind: .keyboard, inventory: all)
        XCTAssertEqual(preferences.mouse, "mouse-a")
        XCTAssertThrowsError(try preferences.validateTarget("keyboard-a", kind: .mouse, inventory: all))
        XCTAssertNoThrow(try preferences.validateTarget("mouse-a", kind: .mouse, inventory: all))
    }
    func testAmbiguousInitialInventoryRequiresChoiceAndOfflineCannotWrite() throws {
        var preferences = DeviceSelection()
        let other = mouse.replacingOccurrences(of: "mouse-a", with: "mouse-b")
        preferences.discover(in: try inventory(mouse + "," + other))
        XCTAssertEqual(preferences.mouse, "")
        let offline = try inventory(mouse.replacingOccurrences(of: "true", with: "false"))
        preferences.mouse = "mouse-a"
        XCTAssertThrowsError(try preferences.validateTarget("mouse-a", kind: .mouse, inventory: offline))
        XCTAssertThrowsError(try preferences.validateTarget("mouse-a", kind: .mouse, inventory: nil))
    }
    func testUnknownLegacyTargetAndUnhealthyInventoryDoNotGuess() throws {
        var preferences = DeviceSelection(); preferences.device = "unidentified"
        preferences.discover(in: try inventory(mouse + "," + keyboard))
        XCTAssertEqual(preferences.mouse, ""); XCTAssertEqual(preferences.keyboard, "")
        preferences = DeviceSelection(); preferences.discover(in: try inventory(mouse, health: "Unavailable"))
        XCTAssertEqual(preferences.mouse, "")
    }
}
