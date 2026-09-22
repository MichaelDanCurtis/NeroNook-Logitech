import AppKit
import SwiftUI
import NookPluginSDK
import LogitechCore

let moduleID = "cafe.nero.plugin.logitech"
struct Preferences: Codable {
    var application = "/Applications/OpenLogi.app"
    var device = ""
}
@MainActor final class ModuleApp: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var status = "Connecting to OpenLogi…"
    @Published var inventory: Inventory?
    @Published var dpi: DPI?
    @Published var wheel: Wheel?
    @Published var busy = false
    @Published var ready = false
    @Published var notice = ""
    @Published var preferences = Preferences()
    @Published var lastRead: Date?
    private let bridge = LogitechBridge()
    private let input = InputReader()
    private var window: NSWindow?
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var timer: Timer?
    private var ticks = 0
    private var visible = true
    private var handledRuns = Set<UUID>()
    let hosted = CommandLine.arguments.contains("--neronook-plugin")
    var executable: URL { URL(fileURLWithPath: preferences.application).appendingPathComponent("Contents/MacOS/openlogi") }
    var selected: Device? { inventory?.devices.first { $0.id == preferences.device } }
    var battery: String { selected?.battery?.percent.map { "\($0)%" } ?? "Unknown" }
    private var storage: URL? { try? PluginStorage.directory(id: moduleID).appendingPathComponent("settings.json") }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let storage, let data = try? Data(contentsOf: storage), let value = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = value }
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
            session = message.session
            emit("ready", features: ["actions-v1", "dashboard-v1", "panels-v1", "diagrams-v1"])
            let target = PluginParameter("device", .string)
            send(.init(.register, registration: .init(actions: [
                .init("read_status", title: "Read Logitech mouse status", output: .init([.init("connected", .boolean), .init("device", .string), .init("message", .string)])),
                .init("set_dpi", title: "Set Logitech mouse DPI", input: .init([target, .init("dpi", .number, minimum: 1, maximum: 65535)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 60),
                .init("set_wheel_mode", title: "Set Logitech wheel mode", input: .init([target, .init("mode", .string)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 60)
            ], channels: [.init("status", title: "Logitech mouse status", kind: .state, schema: .init([.init("connected", .boolean), .init("device", .string), .init("message", .string)]))])))
            refresh(); publish(); return
        }
        guard session == message.session else { NSApp.terminate(nil); return }
        if message.type == "visibility" { visible = message.visible ?? false }
        if message.type == "action" {
            if ["configure", "controls"].contains(message.action ?? "") { showWindow() }
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
    var values: [String: PluginValue] { ["connected": .boolean(ready && !busy), "device": .string(preferences.device), "message": .string(String(status.prefix(280)))] }
    func selectDevice(_ id: String) { guard !busy else { return }; preferences.device = id; save(); ready = false; dpi = nil; wheel = nil; refresh() }
    func chooseApplication() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        panel.message = "Choose the OpenLogi application with the matching CLI and agent (protocol 32)."
        panel.begin { [weak self] response in Task { @MainActor in
            guard response == .OK, let url = panel.url, let self else { return }
            self.preferences.application = url.path; self.save(); self.refresh()
        } }
    }
    func save() { if let storage, let data = try? JSONEncoder().encode(preferences) { do { try data.write(to: storage, options: .atomic) } catch { notice = "Could not save plugin settings." } } }
    func openOpenLogi() { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: preferences.application), configuration: .init()) { _, _ in } }
    func refresh() {
        guard !busy, !hosted || session != nil else { return }; busy = true
        Task {
            defer { busy = false; publish() }
            do {
                let found = try await bridge.inventory(executable); inventory = found
                if preferences.device.isEmpty, let first = found.mice.first(where: { $0.online }) { preferences.device = first.id; save() }
                guard !found.mice.isEmpty else { throw BridgeProblem("No mouse is visible to OpenLogi. Check its agent permissions and your mouse connection.") }
                let target = try found.target(preferences.device)
                let currentDPI = try? await bridge.dpi(executable, id: target.id)
                let currentWheel = try? await bridge.wheel(executable, id: target.id)
                dpi = currentDPI; wheel = currentWheel; ready = true; lastRead = Date()
                status = "\(target.name) · \(battery) battery"
                if currentDPI == nil && currentWheel == nil { status += " · settings unavailable" }
            } catch { unavailable(error) }
        }
    }
    private func unavailable(_ error: Error) {
        ready = false; dpi = nil; wheel = nil
        let raw = error.localizedDescription
        status = raw.localizedCaseInsensitiveContains("skew") || raw.localizedCaseInsensitiveContains("protocol") ? "OpenLogi needs a matching CLI and agent (protocol 32)." : String(raw.prefix(380))
    }
    func applyDPI(_ value: Int, device: String? = nil, request: UUID? = nil) {
        guard !busy else { return }; busy = true; notice = "Applying DPI…"
        let target = device ?? preferences.device
        Task {
            do {
                let result = try await bridge.setDPI(executable, id: target, value: value)
                if target == preferences.device { dpi = result; lastRead = Date() }
                finish("DPI set to \(result.current). Read-back confirmed.", request: request)
            } catch { finish(error.localizedDescription, request: request, failed: true); ready = false }
            busy = false; publish(); refresh()
        }
    }
    func applyWheel(mode: String?, threshold: Int?, device: String? = nil, request: UUID? = nil) {
        guard !busy else { return }; busy = true; notice = "Applying wheel settings…"
        let target = device ?? preferences.device
        Task {
            do {
                let result = try await bridge.setWheel(executable, id: target, mode: mode, threshold: threshold)
                if target == preferences.device { wheel = result; lastRead = Date() }
                finish("Wheel settings confirmed. Other fields were preserved.", request: request)
            } catch { finish(error.localizedDescription, request: request, failed: true); ready = false }
            busy = false; publish(); refresh()
        }
    }
    private func finish(_ text: String, request: UUID?, failed: Bool = false) {
        notice = String(text.prefix(380))
        if let request { send(.init(.update, requestID: request, update: .init(failed ? .failed : .succeeded, message: String(text.prefix(280)), values: failed ? [:] : ["message": .string(String(text.prefix(280)))]))) }
    }
    private func send(_ bus: PluginBusMessage) { emit("bus", bus: bus) }
    private func emit(_ type: String, features: [String]? = nil, snapshot: PluginSnapshot? = nil, bus: PluginBusMessage? = nil) {
        guard let session else { return }; if type != "ready" { sequence += 1 }
        do { try FileHandle.standardOutput.write(contentsOf: PluginMessage(type: type, pluginID: moduleID, session: session, sequence: sequence, snapshot: snapshot, features: features, bus: bus).encoded()) }
        catch { NSApp.terminate(nil) }
    }
    func publish() {
        let snapshot = PluginSnapshot(title: selected?.name ?? "Logitech", status: status,
            activity: ready ? "Mouse · \(dpi.map { "\($0.current) DPI" } ?? battery)" : "Logitech · unavailable",
            fields: [.init(ready ? "Battery" : "Last known battery", battery, symbol: "battery.75percent"), .init("Connection", ready ? "OpenLogi" : "Unavailable")],
            actions: [.init("controls", "Mouse controls", symbol: "slider.horizontal.3"), .init("refresh", "Refresh", enabled: !busy, symbol: "arrow.clockwise"), .init("open_app", "OpenLogi", symbol: "arrow.up.forward.app")],
            badge: busy ? "Updating" : ready ? "Connected" : "Setup needed",
            panels: [.init("mouse", "Mouse", diagrams: [mouseDiagram(dpi: dpi?.current, wheel: wheel?.mode, battery: battery, connected: ready)]),
                     .init("connection", "Connection", sections: [.init("OpenLogi", preferences.application), .init("Last verified", lastRead?.formatted(date: .omitted, time: .standard) ?? "No live response yet"), .init("Settings ownership", "Temporary mouse adjustments here. OpenLogi owns saved profiles, gestures and button mappings."), .init("Latest action", notice.isEmpty ? "No settings changed in this session." : notice)])])
        emit("snapshot", snapshot: snapshot); send(.init(.publish, address: .init(moduleID, "status"), values: values, lifetime: 8))
    }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 590), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Logitech mouse controls"; w.contentView = NSHostingView(rootView: SettingsView(model: self)); w.isReleasedWhenClosed = false; w.center(); window = w
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
