import XCTest
@testable import LogitechCore

final class KeyboardEventTests: XCTestCase {
    func inventory(online: Bool = true, battery: Int? = 70, id: String = "keyboard", health: String = "Ready", absent: Bool = false, duplicate: Bool = false) -> Inventory {
        let keyboard = Device(id: id, name: "Fixture keyboard", online: online,
                              battery: .init(percentage: battery, status: nil), capabilities: .init(pointer: false, buttons: true))
        return .init(schemaVersion: 1, protocolVersion: 32, agentVersion: "fixture", inventoryHealth: health,
                     devices: absent ? [] : duplicate ? [keyboard, keyboard] : [keyboard])
    }
    func observe(_ tracker: inout KeyboardEventTracker, _ value: Inventory, time: Double = 100, selected: String = "keyboard", threshold: Int = 20, enabled: Bool = true) -> [KeyboardEventTracker.Event] {
        tracker.observe(value, selected: selected, threshold: threshold, enabled: enabled, at: Date(timeIntervalSince1970: time))
    }
    func testInitialAlreadyLowAndRestartAreQuiet() {
        var first = KeyboardEventTracker(), restarted = KeyboardEventTracker()
        XCTAssertTrue(observe(&first, inventory(battery: 5)).isEmpty)
        XCTAssertTrue(observe(&first, inventory(battery: 5), time: 106).isEmpty)
        XCTAssertTrue(observe(&restarted, inventory(battery: 5), time: 106).isEmpty)
    }
    func testHealthyDisappearanceAndReconnectionEmitExactlyOnce() {
        var tracker = KeyboardEventTracker()
        _ = observe(&tracker, inventory())
        let off = observe(&tracker, inventory(absent: true), time: 106)
        XCTAssertEqual(off.map(\.kind), ["disconnected"]); XCTAssertFalse(off[0].connected); XCTAssertNil(off[0].battery)
        XCTAssertTrue(observe(&tracker, inventory(absent: true), time: 112).isEmpty)
        let on = observe(&tracker, inventory(battery: 12), time: 118)
        XCTAssertEqual(on.map(\.kind), ["connected"]); XCTAssertNotEqual(off[0].id, on[0].id)
        XCTAssertEqual(on[0].device, "keyboard"); XCTAssertEqual(on[0].battery, 12)
    }
    func testLowBatteryHysteresisDoesNotRepeatOnOscillation() {
        var tracker = KeyboardEventTracker()
        _ = observe(&tracker, inventory(battery: 21))
        XCTAssertEqual(observe(&tracker, inventory(battery: 20), time: 106).map(\.kind), ["low_battery"])
        for (time, value) in [(112.0,21), (118,19), (124,24)] {
            XCTAssertTrue(observe(&tracker, inventory(battery: value), time: time).isEmpty)
        }
        XCTAssertEqual(observe(&tracker, inventory(battery: 25), time: 130).map(\.kind), ["battery_recovered"])
        XCTAssertTrue(observe(&tracker, inventory(battery: 25), time: 136).isEmpty)
    }
    func testServiceFailureAndSleepCannotFabricateDisconnectOrReplay() {
        var tracker = KeyboardEventTracker()
        _ = observe(&tracker, inventory())
        XCTAssertTrue(observe(&tracker, inventory(health: "Unavailable", absent: true), time: 106).isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(online: false), time: 112).isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(), time: 200).isEmpty)
        XCTAssertEqual(observe(&tracker, inventory(online: false), time: 206).map(\.kind), ["disconnected"])
    }
    func testUnknownInvalidBatteryReestablishesBaseline() {
        var tracker = KeyboardEventTracker()
        _ = observe(&tracker, inventory())
        XCTAssertTrue(observe(&tracker, inventory(battery: -1), time: 106).isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(battery: 5), time: 112).isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(battery: nil), time: 118).isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(battery: 1000), time: 124).isEmpty)
    }
    func testChangedTargetAmbiguityDisableAndThresholdResetQuietly() {
        var tracker = KeyboardEventTracker()
        _ = observe(&tracker, inventory())
        XCTAssertTrue(observe(&tracker, inventory(id: "other"), time: 106, selected: "other").isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(online: false, id: "other", duplicate: true), time: 112, selected: "other").isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(id: "other"), time: 118, selected: "other").isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(online: false, id: "other"), time: 124, selected: "other", enabled: false).isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(online: false, id: "other"), time: 130, selected: "other").isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(battery: 40, id: "other"), time: 136, selected: "other", threshold: 45).isEmpty)
    }
    func testOldDuplicateTimeAndInvalidThresholdCannotCreateEvent() {
        var tracker = KeyboardEventTracker()
        _ = observe(&tracker, inventory())
        XCTAssertTrue(observe(&tracker, inventory(online: false), time: 100).isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(online: false), time: 99).isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(online: false), time: 106, threshold: 0).isEmpty)
        XCTAssertTrue(observe(&tracker, inventory(), time: 112).isEmpty)
    }
    func testLegacyPreferencesKeepWatchOffAndExactTargets() throws {
        let value = try JSONDecoder().decode(DeviceSelection.self, from: Data(#"{"application":"/fixture","keyboard":"remembered","mouse":"old-mouse"}"#.utf8))
        XCTAssertFalse(value.keyboardEvents); XCTAssertEqual(value.keyboardLowBattery, 20)
        XCTAssertEqual(value.keyboard, "remembered"); XCTAssertEqual(value.mouse, "old-mouse")
        XCTAssertThrowsError(try JSONDecoder().decode(DeviceSelection.self, from: Data(#"{"keyboardLowBattery":99}"#.utf8)))
    }
}
