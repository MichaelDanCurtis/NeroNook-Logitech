import AppKit
import Darwin
import SwiftUI
import NookPluginSDK
import LogitechCore

let moduleID = "cafe.nero.plugin.logitech"
@MainActor final class ModuleApp: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var status = "Connecting to OpenLogi…"
    @Published var inventory: Inventory?
    @Published var dpi: DPI?
    @Published var wheel: Wheel?
    @Published var busy = false
    @Published var inventoryFresh = false
    @Published var notice = ""
    @Published var preferences = DeviceSelection()
    @Published var lastRead: Date?
    @Published var showSetup = false
    @Published var lastKeyboardEvent = "No event observed"
    private var keyboardEventTracker = KeyboardEventTracker()
    private let bridge = LogitechBridge(format: .automatic)
    @Published var hostSwitchSupported = false
    private var hostSwitchLive = false
    @Published var hostSwitchStatus = "Easy-Switch events are off"
    private var hostSwitchProcess: HostSwitchProcess?
    private var hostSwitchGeneration = UUID()
    private let input = InputReader()
    private var window: NSWindow?
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var timer: Timer?
    private var terminationSignal: DispatchSourceSignal?
    private var ticks = 0
    private var visible = true
    private var customViews = false
    private var handledRuns = Set<UUID>()
    let hosted = CommandLine.arguments.contains("--neronook-plugin")
    var executable: URL { URL(fileURLWithPath: preferences.application).appendingPathComponent("Contents/MacOS/openlogi") }
    var selected: Device? { device(preferences.tab) }
    func device(_ kind: DeviceKind) -> Device? { inventory?.devices.first { $0.id == preferences.id(for: kind) && kind.matches($0) } }
    func ready(_ kind: DeviceKind) -> Bool { inventoryFresh && (try? inventory?.target(preferences.id(for: kind))) != nil }
    func battery(_ kind: DeviceKind) -> String { device(kind)?.battery?.percentage.map { "\($0)%" } ?? "Unknown" }
    private var fixtureRoot: URL? {
        guard let index = CommandLine.arguments.firstIndex(of: "--protocol-fixture"),
              index + 1 < CommandLine.arguments.count,
              let id = UUID(uuidString: CommandLine.arguments[index + 1]) else { return nil }
        return FileManager.default.temporaryDirectory.appendingPathComponent("nn-logi-fixture-" + id.uuidString.lowercased())
    }
    private var storage: URL? {
        if CommandLine.arguments.contains("--protocol-fixture") { return fixtureRoot?.appendingPathComponent("settings.json") }
        return try? PluginStorage.directory(id: moduleID).appendingPathComponent("settings.json")
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // The host stops native modules with SIGTERM. Handle it on the main
        // queue so the owned read-only CLI cannot survive its parent restart.
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler { [weak self] in
            self?.stopHostSwitchProcess(); NSApp.terminate(nil)
        }
        terminationSignal = termination; termination.resume()
        if let storage, let data = try? Data(contentsOf: storage), let value = try? JSONDecoder().decode(DeviceSelection.self, from: data) { preferences = value }
        if CommandLine.arguments.contains("--protocol-fixture") {
            guard let root = fixtureRoot, let storage, FileManager.default.fileExists(atPath: storage.path),
                  URL(fileURLWithPath: preferences.application).standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else {
                NSApp.terminate(nil); return
            }
        }
        if hosted {
            input.start { [weak self] message in Task { @MainActor in
                guard let message else { NSApp.terminate(nil); return }; self?.receive(message)
            } }
        } else { showWindow(); refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.publish(); self.ticks += 1
            if self.ticks % (self.visible || self.preferences.keyboardEvents ? 3 : 15) == 0 { self.refresh() }
        } }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); stopHostSwitchProcess(); terminationSignal?.cancel()
    }
    private func receive(_ message: PluginMessage) {
        guard message.pluginID == moduleID else { NSApp.terminate(nil); return }
        if session == nil {
            guard message.type == "hello" else { NSApp.terminate(nil); return }
            session = message.session; PluginAppearanceStore.shared.beginSession(pluginID:moduleID,session:message.session); customViews = message.features?.contains("custom-views-v1") == true
            emit("ready", features: ["appearance-v1", "actions-v1", "dashboard-v1", "panels-v1"] + (customViews ? ["custom-views-v1"] : []))
            let target = PluginParameter("device", .string)
            send(.init(.register, registration: .init(actions: [
                .init("read_status", title: "Read Logitech device status", output: .init([.init("connected", .boolean), .init("device", .string), .init("message", .string)])),
                .init("set_dpi", title: "Set Logitech mouse DPI", input: .init([target, .init("dpi", .number, minimum: 1, maximum: 65535)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 60),
                .init("set_wheel_mode", title: "Set Logitech wheel mode", input: .init([target, .init("mode", .string)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 60)
            ], channels: [
                .init("status", title: "Logitech device status", kind: .state, schema: .init([.init("connected", .boolean), .init("device", .string), .init("message", .string)])),
                .init("keyboard_events", title: "Logitech keyboard connection and battery changes", kind: .event,
                      schema: .init([.init("event_id", .string), .init("device", .string), .init("kind", .string),
                                     .init("connected", .boolean), .init("battery", .number, required: false, minimum: 0, maximum: 100),
                                     .init("observed_at", .number, minimum: 0), .init("message", .string)]))
            ] + [
                .init("host_switch_choices", title: "Keyboard Easy-Switch choices", kind: .event,
                      schema: .init([.init("event_id", .string), .init("device", .string), .init("channel", .number, minimum: 1, maximum: 3), .init("observed_at", .number, minimum: 0)])),
                .init("host_switch_status", title: "Selected keyboard Easy-Switch watch", kind: .state,
                      schema: .init([.init("device", .string), .init("name", .string), .init("watching", .boolean), .init("supported", .boolean)]))
            ])))
            refresh(); publish(); return
        }
        guard session == message.session else { NSApp.terminate(nil); return }; if message.type == "appearance" { _ = PluginAppearanceStore.shared.receive(message); return }
        if message.type == "visibility" { visible = message.visible ?? false }
        if message.type == "viewEvent", let event = message.viewEvent {
            do { try handleView(event) } catch { notice = error.localizedDescription }; publish(); return
        }
        if message.type == "action" {
            if message.action == "configure" { showSetup = true; showWindow() }
            if message.action == "controls" { showWindow() }
            if message.action == "refresh" { refresh() }
            if message.action == "open_app" { openOpenLogi() }
        }
        if message.type == "bus", let bus = message.bus, bus.operation == .execute { execute(bus) }
    }
    private func execute(_ bus: PluginBusMessage) {
        guard bus.address?.plugin == moduleID, !handledRuns.contains(bus.requestID), handledRuns.count < 1000 else { send(.init(.update, requestID: bus.requestID, update: .init(.failed, message: "Duplicate request or session limit reached."))); return }
        handledRuns.insert(bus.requestID)
        if bus.address?.name == "read_status" {
            send(.init(.update, requestID: bus.requestID, update: .init(.succeeded, values: values))); return
        }
        guard !busy, case .string(let device)? = bus.values?["device"], !device.isEmpty else { send(.init(.update, requestID: bus.requestID, update: .init(.failed, message: "Choose an exact device and wait for the current operation."))); return }
        if bus.address?.name == "set_dpi", case .number(let value)? = bus.values?["dpi"], value.isFinite, value.rounded() == value, (1...65535).contains(value) {
            applyDPI(Int(value), device: device, request: bus.requestID)
        } else if bus.address?.name == "set_wheel_mode", case .string(let mode)? = bus.values?["mode"], ["free", "ratchet"].contains(mode) {
            applyWheel(mode: mode, threshold: nil, device: device, request: bus.requestID)
        } else { send(.init(.update, requestID: bus.requestID, update: .init(.failed, message: "Unsupported action or invalid setting."))) }
    }
    var values: [String: PluginValue] { ["connected": .boolean(ready(preferences.tab) && !busy), "device": .string(preferences.id(for: preferences.tab)), "message": .string(String(status.prefix(280)))] }
    func selectDevice(_ id: String, kind: DeviceKind) throws {
        guard !busy, let inventory else { throw BridgeProblem("Wait for OpenLogi to finish refreshing.") }
        if kind == .keyboard && id != preferences.keyboard && preferences.hostSwitchEvents { throw BridgeProblem("Stop Easy-Switch watching before choosing another keyboard.") }
        try preferences.select(id, kind: kind, inventory: inventory); save()
        if kind == .mouse { dpi = nil; wheel = nil }
        notice = ""; refresh()
    }
    func chooseApplication() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        panel.message = "Choose the OpenLogi application with the matching CLI and agent."
        panel.begin { [weak self] response in Task { @MainActor in
            guard response == .OK, let url = panel.url, let self else { return }
            self.stopHostSwitchProcess(); self.hostSwitchSupported = false
            self.preferences.application = url.path; self.inventoryFresh = false; self.dpi = nil; self.wheel = nil
            self.save(); self.refresh()
        } }
    }
    func save() { if let storage, let data = try? JSONEncoder().encode(preferences) { do { try data.write(to: storage, options: .atomic) } catch { notice = "Could not save plugin settings." } } }
    func openOpenLogi() { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: preferences.application), configuration: .init()) { [weak self] _, error in
        if let error { Task { @MainActor in self?.notice = "OpenLogi could not open: \(error.localizedDescription)" } }
    } }
    func refresh() {
        guard !busy, !hosted || session != nil else { return }; busy = true
        Task {
            defer { busy = false; publish() }
            do {
                let found = try await bridge.inventory(executable)
                inventory = found; preferences.discover(in: found); save()
                guard found.inventoryHealth == "Ready" else { throw BridgeProblem("OpenLogi is not ready. Check its agent and device permissions.") }
                hostSwitchSupported = (try? await bridge.supportsHostSwitch(executable)) == true
                if preferences.hostSwitchEvents, hostSwitchSupported, hostSwitchProcess == nil { startHostSwitchProcess() }
                observeKeyboard(found)
                var currentDPI: DPI?, currentWheel: Wheel?
                if let target = try? found.pointerTarget(preferences.mouse) {
                    currentDPI = try? await bridge.dpi(executable, id: target.id)
                    currentWheel = try? await bridge.wheel(executable, id: target.id)
                }
                dpi = currentDPI; wheel = currentWheel; inventoryFresh = true; lastRead = Date()
                status = DeviceKind.allCases.map { "\($0.title) · \(ready($0) ? battery($0) : "unavailable")" }.joined(separator: "   ")
            } catch {
                keyboardEventTracker.reset()
                inventoryFresh = false; dpi = nil; wheel = nil
                let raw = error.localizedDescription
                status = raw.localizedCaseInsensitiveContains("skew") || raw.localizedCaseInsensitiveContains("protocol") ? "OpenLogi needs a matching CLI and agent." : String(raw.prefix(280))
            }
        }
    }
    private func observeKeyboard(_ found: Inventory) {
        for event in keyboardEventTracker.observe(found, selected: preferences.keyboard,
                                                  threshold: preferences.keyboardLowBattery, enabled: preferences.keyboardEvents) {
            var values: [String: PluginValue] = ["event_id": .string(event.id.uuidString), "device": .string(event.device),
                "kind": .string(event.kind), "connected": .boolean(event.connected),
                "observed_at": .number(event.observedAt.timeIntervalSince1970), "message": .string(event.message)]
            if let battery = event.battery { values["battery"] = .number(Double(battery)) }
            lastKeyboardEvent = event.message + " · " + event.observedAt.formatted(date: .omitted, time: .standard)
            send(.init(.publish, requestID: event.id, address: .init(moduleID, "keyboard_events"), values: values))
        }
    }
    func configureHostSwitchEvents(device: String, enabled: Bool) throws {
        guard !busy, device == preferences.keyboard, !device.isEmpty, !enabled || hostSwitchSupported else { throw BridgeProblem("Refresh the selected keyboard and use OpenLogi with its host-switch event API.") }
        if !enabled { stopHostSwitchProcess(); preferences.hostSwitchEvents = false; save() }
        busy = true; notice = "Saving the keyboard host-button watch in OpenLogi…"
        Task {
            defer { busy = false; publish() }
            do {
                try await bridge.setHostSwitchEvents(executable, id: device, enabled: enabled)
                guard device == preferences.keyboard else { throw BridgeProblem("The selected keyboard changed.") }
                stopHostSwitchProcess(); preferences.hostSwitchEvents = enabled; save()
                if enabled { startHostSwitchProcess() }
                else { hostSwitchStatus = "Easy-Switch events are off" }
                notice = enabled ? "OpenLogi saved the host-button watch. Waiting for a physical press." : "OpenLogi saved the disabled host-button watch."
            } catch { notice = enabled ? error.localizedDescription : "Local watch stopped; OpenLogi did not confirm disabling its setting. No retry was sent." }
        }
    }
    private func stopHostSwitchProcess() {
        hostSwitchGeneration = UUID(); hostSwitchLive = false; hostSwitchProcess?.stop(); hostSwitchProcess = nil
    }
    private func startHostSwitchProcess() {
        guard hostSwitchProcess == nil, preferences.hostSwitchEvents, !preferences.keyboard.isEmpty else { return }
        let generation = UUID(); hostSwitchGeneration = generation
        let stream = HostSwitchProcess(); hostSwitchProcess = stream
        do {
            try stream.start(executable: executable, device: preferences.keyboard, choice: { [weak self] event in Task { @MainActor in
                guard let self, self.hostSwitchGeneration == generation, self.preferences.hostSwitchEvents, self.preferences.keyboard == event.device else { return }
                let id = UUID()
                self.hostSwitchStatus = "Channel \(event.channel) chosen"
                self.send(.init(.publish, requestID: id, address: .init(moduleID, "host_switch_choices"), values: ["event_id": .string(id.uuidString), "device": .string(event.device), "channel": .number(Double(event.channel)), "observed_at": .number(event.observedAt)])); self.publish()
            } }, status: { [weak self] status, live in Task { @MainActor in
                guard let self, self.hostSwitchGeneration == generation else { return }; self.hostSwitchStatus = status; self.hostSwitchLive = live; self.publish()
            } })
        } catch { hostSwitchStatus = "Could not start the OpenLogi host-button stream."; stopHostSwitchProcess() }
    }
    func configureKeyboardEvents(device: String, enabled: Bool, threshold: Int) throws {
        guard !busy, device == preferences.keyboard, !device.isEmpty, (1...50).contains(threshold) else {
            throw BridgeProblem("Select the keyboard and a battery threshold of 1–50% before changing its watch.")
        }
        if enabled {
            guard inventoryFresh, let inventory,
                  inventory.devices.filter({ $0.id == device && $0.isKeyboard }).count == 1 else {
                throw BridgeProblem("Refresh the selected keyboard before enabling its watch.")
            }
        }
        preferences.keyboardEvents = enabled; preferences.keyboardLowBattery = threshold
        keyboardEventTracker.reset(); lastKeyboardEvent = enabled ? "Watching from a fresh baseline" : "Keyboard events are off"
        save(); publish(); refresh()
    }
    func applyDPI(_ value: Int, device: String, request: UUID? = nil) {
        guard !busy else { return }; busy = true; notice = "Applying DPI…"
        Task {
            do {
                let result = try await bridge.setDPI(executable, id: device, value: value)
                if device == preferences.mouse { dpi = result; lastRead = Date() }
                finish("DPI set to \(result.current). Read-back confirmed.", request: request)
            } catch { finish(error.localizedDescription, request: request, failed: true); inventoryFresh = false }
            busy = false; publish(); refresh()
        }
    }
    func applyWheel(mode: String?, threshold: Int?, device: String, request: UUID? = nil) {
        guard !busy else { return }; busy = true; notice = "Applying wheel settings…"
        Task {
            do {
                let result = try await bridge.setWheel(executable, id: device, mode: mode, threshold: threshold)
                if device == preferences.mouse { wheel = result; lastRead = Date() }
                finish("Wheel settings confirmed. Other fields were preserved.", request: request)
            } catch { finish(error.localizedDescription, request: request, failed: true); inventoryFresh = false }
            busy = false; publish(); refresh()
        }
    }
    private func finish(_ text: String, request: UUID?, failed: Bool = false) {
        notice = String(text.prefix(280))
        if let request { send(.init(.update, requestID: request, update: .init(failed ? .failed : .succeeded, message: notice, values: failed ? [:] : ["message": .string(notice)]))) }
    }
    private func send(_ bus: PluginBusMessage) { emit("bus", bus: bus) }
    private func emit(_ type: String, features: [String]? = nil, snapshot: PluginSnapshot? = nil, bus: PluginBusMessage? = nil) {
        guard let session else { return }; if type != "ready" { sequence += 1 }
        do { try FileHandle.standardOutput.write(contentsOf: PluginMessage(type: type, pluginID: moduleID, session: session, sequence: sequence, snapshot: snapshot, features: features, bus: bus).encoded()) }
        catch { NSApp.terminate(nil) }
    }
    func publish() {
        let panels = DeviceKind.allCases.map { kind in
            customViews ? PluginPanel(kind.rawValue, kind.title, customView: surface(kind)) : PluginPanel(kind.rawValue, kind.title, sections: [.init(device(kind)?.name ?? kind.title, "Open Device controls for the interactive view. This host needs custom view support (NeroNook 0.21 or newer).")])
        }
        let snapshot = PluginSnapshot(title: "Logitech", status: status, activity: String(status.prefix(100)),
            actions: customViews ? [] : [.init("controls", "Device controls", symbol: "slider.horizontal.3"), .init("configure", "Setup", symbol: "gearshape")],
            badge: busy ? "Updating" : inventoryFresh ? "Connected" : "Setup needed", panels: panels)
        emit("snapshot", snapshot: snapshot)
        send(.init(.publish, address: .init(moduleID, "host_switch_status"), values: ["device": .string(preferences.keyboard), "name": .string(device(.keyboard)?.name ?? "Selected keyboard"), "watching": .boolean(preferences.hostSwitchEvents && hostSwitchLive), "supported": .boolean(hostSwitchSupported)], lifetime: 8))
        send(.init(.publish, address: .init(moduleID, "status"), values: values, lifetime: 8))
    }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 490), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Logitech devices"; w.contentView = NSHostingView(rootView: DeviceWindow(model: self).pluginThemed()); w.isReleasedWhenClosed = false; w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
private final class InputReader: @unchecked Sendable {
    private var lines = PluginLines()
    private let queue = DispatchQueue(label: "LogitechPlugin.input")
    func start(_ receive: @escaping @Sendable (PluginMessage?) -> Void) {
        FileHandle.standardInput.readabilityHandler = { [weak self] file in
            let data = file.availableData; guard !data.isEmpty else { receive(nil); return }
            self?.queue.async { [weak self] in
                guard let self else { return }
                do { for message in try self.lines.append(data) { receive(message) } } catch { receive(nil) }
            }
        }
    }
}
