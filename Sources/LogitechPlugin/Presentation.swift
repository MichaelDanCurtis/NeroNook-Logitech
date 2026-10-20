import SwiftUI
import NookPluginSDK
import LogitechCore

@MainActor extension ModuleApp {
    func surface(_ kind: DeviceKind) -> PluginCustomView {
        let current = device(kind)
        let candidates = inventory?.devices.filter { kind.matches($0) }.prefix(16).map { ["id": $0.id, "name": $0.name, "online": $0.online ? "true" : "false"] } ?? []
        var state: [String: PluginValue] = [
            "kind": .string(kind.rawValue), "device": .string(preferences.id(for: kind)),
            "name": .string(current?.name ?? "Choose a \(kind.rawValue)"),
            "devices": .string(String(decoding: (try? JSONEncoder().encode(candidates)) ?? Data("[]".utf8), as: UTF8.self)),
            "ready": .boolean(ready(kind)), "busy": .boolean(busy), "battery": .string(battery(kind)),
            "power": .string(current?.battery?.status?.capitalized ?? "Unknown"),
            "notice": .string(notice), "status": .string(status),
            "last_read": .string(lastRead?.formatted(date: .omitted, time: .standard) ?? "Never"),
            "art": .string(current?.name.lowercased().contains(kind == .mouse ? "mx master 3" : "mx keys s") == true ? kind.rawValue : "generic")
        ]
        state["events_enabled"] = .boolean(preferences.keyboardEvents)
        state["events_ready"] = .boolean(inventoryFresh && current != nil)
        state["host_switch_supported"] = .boolean(hostSwitchSupported)
        state["host_switch_enabled"] = .boolean(preferences.hostSwitchEvents)
        state["host_switch_status"] = .string(hostSwitchStatus)
        state["low_battery"] = .number(Double(preferences.keyboardLowBattery))
        state["last_event"] = .string(lastKeyboardEvent)
        if kind == .mouse {
            state["dpi"] = .number(Double(dpi?.current ?? 0))
            state["dpi_values"] = .string(String(decoding: (try? JSONEncoder().encode(dpi?.capabilities.values ?? [])) ?? Data("[]".utf8), as: UTF8.self))
            state["mode"] = .string(wheel?.mode.lowercased() ?? "")
            state["threshold"] = .number(Double(wheel?.autoDisengage ?? 0))
        }
        let target = PluginParameter("device", .string)
        return .init(entry: "devices/index.html", revision: "devices5", state: state, events: [
            .init("select", input: .init([target])), .init("refresh"), .init("settings"), .init("mappings"),
            .init("dpi", input: .init([target, .init("value", .number, minimum: 1, maximum: 65535)])),
            .init("wheel", input: .init([target, .init("mode", .string)])),
            .init("threshold", input: .init([target, .init("value", .number, minimum: 1, maximum: 255)])),
            .init("host_watch", input: .init([target, .init("enabled", .boolean)])),
            .init("keyboard_watch", input: .init([target, .init("enabled", .boolean), .init("threshold", .number, minimum: 1, maximum: 50)]))
        ])
    }
    func handleView(_ event: PluginViewEvent) throws {
        guard let kind = DeviceKind(rawValue: event.panelID) else { throw BridgeProblem("Unknown device tab.") }
        try surface(kind).validate(event)
        func text(_ key: String) -> String { if case .string(let value) = event.values[key] { return value }; return "" }
        func number() throws -> Int {
            guard case .number(let value) = event.values["value"], value.isFinite, value.rounded() == value else { throw BridgeProblem("Choose a whole-number setting.") }
            return Int(value)
        }
        switch event.name {
        case "select": try selectDevice(text("device"), kind: kind)
        case "refresh": refresh()
        case "settings": showSetup = true; showWindow()
        case "mappings": openOpenLogi()
        case "host_watch":
            guard kind == .keyboard, case .boolean(let enabled) = event.values["enabled"] else { throw BridgeProblem("Choose the keyboard host-button watch.") }
            try configureHostSwitchEvents(device: text("device"), enabled: enabled)
        case "keyboard_watch":
            guard kind == .keyboard, case .boolean(let enabled) = event.values["enabled"],
                  case .number(let threshold) = event.values["threshold"], threshold.rounded() == threshold else {
                throw BridgeProblem("Keyboard watch requires a whole-number battery threshold.")
            }
            try configureKeyboardEvents(device: text("device"), enabled: enabled, threshold: Int(threshold))
        case "dpi", "wheel", "threshold":
            guard kind == .mouse, ready(kind), !busy else { throw BridgeProblem("Wait for a connected mouse before applying.") }
            try preferences.validateTarget(text("device"), kind: kind, inventory: inventory)
            if event.name == "dpi" {
                let value = try number()
                guard dpi?.capabilities.values.contains(value) == true else { throw BridgeProblem("That DPI is unavailable for this mouse.") }
                applyDPI(value, device: text("device"))
            } else {
                guard wheel != nil else { throw BridgeProblem("Wheel settings are unavailable.") }
                if event.name == "wheel" {
                    guard ["free", "ratchet"].contains(text("mode")) else { throw BridgeProblem("Choose a supported wheel mode.") }
                    applyWheel(mode: text("mode"), threshold: nil, device: text("device"))
                } else { applyWheel(mode: nil, threshold: try number(), device: text("device")) }
            }
        default: throw BridgeProblem("Unknown control.")
        }
    }
}
struct DeviceWindow: View {
    @ObservedObject var model: ModuleApp
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logitech").font(.headline)
                Spacer()
                Picker("Device type", selection: Binding(get: { model.preferences.tab }, set: { model.preferences.tab = $0; model.save() })) {
                    Text("Mouse").tag(DeviceKind.mouse); Text("Keyboard").tag(DeviceKind.keyboard)
                }.pickerStyle(.segmented).frame(width: 230)
                Spacer()
                Text("OpenLogi").font(.caption).pluginSecondaryText()
            }.padding(.horizontal, 20).frame(height: 40)
            PluginWebSurface(root: Bundle.main.resourceURL!.appendingPathComponent("Views"), panelID: model.preferences.tab.rawValue, definition: model.surface(model.preferences.tab)) { event in
                do { try model.handleView(event) } catch { model.notice = error.localizedDescription }
            }.frame(width: 800, height: 450)
        }.background(Color.clear)
        .sheet(isPresented: $model.showSetup) {
            PluginSettingsPage("Logitech", subtitle: "Mouse and keyboard controls, connected through OpenLogi.", symbol: "keyboard", width: 650, height: 570, done: { model.showSetup = false }) {
                PluginSettingsSection("OpenLogi connection") {
                    Text("OpenLogi manages your devices, profiles and mappings. NeroNook reads status and makes temporary mouse adjustments through its agent.").font(.callout).pluginSecondaryText()
                    Text(model.status)
                    Button("Open OpenLogi") { model.openOpenLogi() }
                }
                PluginAdvancedSection(detail: "Choose another OpenLogi installation or inspect connection details. Easy-Switch keeps its normal keyboard behavior; backlight and Fn lock remain in OpenLogi.") {
                LabeledContent("Application", value: model.preferences.application).font(.callout).textSelection(.enabled)
                LabeledContent("Last response", value: model.lastRead?.formatted() ?? "No response yet")
                Text(model.status).pluginSecondaryText()
                Text("Easy-Switch observation needs OpenLogi’s host-switch event API. The keyboard retains its normal channel behavior. Backlight and Fn lock remain in OpenLogi.").font(.callout)
                Button("Choose OpenLogi…") { model.chooseApplication() }.disabled(model.busy)
                }
            }
        }
    }
}
