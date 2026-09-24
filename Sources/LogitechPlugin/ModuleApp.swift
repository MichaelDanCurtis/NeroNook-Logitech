import AppKit
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
    private let bridge = LogitechBridge()
    private let input = InputReader()
    private var window: NSWindow?
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var timer: Timer?
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
    private var storage: URL? { try? PluginStorage.directory(id: moduleID).appendingPathComponent("settings.json") }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let storage, let data = try? Data(contentsOf: storage), let value = try? JSONDecoder().decode(DeviceSelection.self, from: data) { preferences = value }
        if hosted {
            input.start { [weak self] message in Task { @MainActor in
                guard let message else { NSApp.terminate(nil); return }; self?.receive(message)
            } }
        } else { showWindow(); refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.publish(); self.ticks += 1
            if self.ticks % (self.visible ? 3 : 15) == 0 { self.refresh() }
        } }
    }
    private func receive(_ message: PluginMessage) {
        guard message.pluginID == moduleID else { NSApp.terminate(nil); return }
        if session == nil {
            guard message.type == "hello" else { NSApp.terminate(nil); return }
            session = message.session; customViews = message.features?.contains("custom-views-v1") == true
            emit("ready", features: ["actions-v1", "dashboard-v1", "panels-v1"] + (customViews ? ["custom-views-v1"] : []))
            let target = PluginParameter("device", .string)
            send(.init(.register, registration: .init(actions: [
                .init("read_status", title: "Read Logitech device status", output: .init([.init("connected", .boolean), .init("device", .string), .init("message", .string)])),
                .init("set_dpi", title: "Set Logitech mouse DPI", input: .init([target, .init("dpi", .number, minimum: 1, maximum: 65535)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 60),
                .init("set_wheel_mode", title: "Set Logitech wheel mode", input: .init([target, .init("mode", .string)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 60)
            ], channels: [.init("status", title: "Logitech device status", kind: .state, schema: .init([.init("connected", .boolean), .init("device", .string), .init("message", .string)]))])))
            refresh(); publish(); return
        }
        guard session == message.session else { NSApp.terminate(nil); return }
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
        try preferences.select(id, kind: kind, inventory: inventory); save()
        if kind == .mouse { dpi = nil; wheel = nil }
        notice = ""; refresh()
    }
    func chooseApplication() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        panel.message = "Choose the OpenLogi application with the matching CLI and agent (protocol 32)."
        panel.begin { [weak self] response in Task { @MainActor in
            guard response == .OK, let url = panel.url, let self else { return }
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
                var currentDPI: DPI?, currentWheel: Wheel?
                if let target = try? found.pointerTarget(preferences.mouse) {
                    currentDPI = try? await bridge.dpi(executable, id: target.id)
                    currentWheel = try? await bridge.wheel(executable, id: target.id)
                }
                dpi = currentDPI; wheel = currentWheel; inventoryFresh = true; lastRead = Date()
                status = DeviceKind.allCases.map { "\($0.title) · \(ready($0) ? battery($0) : "unavailable")" }.joined(separator: "   ")
            } catch {
                inventoryFresh = false; dpi = nil; wheel = nil
                let raw = error.localizedDescription
                status = raw.localizedCaseInsensitiveContains("skew") || raw.localizedCaseInsensitiveContains("protocol") ? "OpenLogi needs a matching CLI and agent (protocol 32)." : String(raw.prefix(280))
            }
        }
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
        emit("snapshot", snapshot: snapshot); send(.init(.publish, address: .init(moduleID, "status"), values: values, lifetime: 8))
    }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 490), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Logitech devices"; w.contentView = NSHostingView(rootView: DeviceWindow(model: self)); w.isReleasedWhenClosed = false; w.center(); window = w
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
