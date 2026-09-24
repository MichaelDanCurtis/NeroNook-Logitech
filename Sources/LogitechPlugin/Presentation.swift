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
        if kind == .mouse {
            state["dpi"] = .number(Double(dpi?.current ?? 0))
            state["dpi_values"] = .string(String(decoding: (try? JSONEncoder().encode(dpi?.capabilities.values ?? [])) ?? Data("[]".utf8), as: UTF8.self))
            state["mode"] = .string(wheel?.mode.lowercased() ?? "")
            state["threshold"] = .number(Double(wheel?.autoDisengage ?? 0))
        }
        let target = PluginParameter("device", .string)
        return .init(entry: "devices/index.html", revision: "devices3", state: state, events: [
            .init("select", input: .init([target])), .init("refresh"), .init("settings"), .init("mappings"),
            .init("dpi", input: .init([target, .init("value", .number, minimum: 1, maximum: 65535)])),
            .init("wheel", input: .init([target, .init("mode", .string)])),
            .init("threshold", input: .init([target, .init("value", .number, minimum: 1, maximum: 255)]))
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
                Text("OpenLogi").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).frame(height: 40)
            PluginWebSurface(root: Bundle.main.resourceURL!.appendingPathComponent("Views"), panelID: model.preferences.tab.rawValue, definition: model.surface(model.preferences.tab)) { event in
                do { try model.handleView(event) } catch { model.notice = error.localizedDescription }
            }.frame(width: 800, height: 450)
        }.background(Color(red: 0.052, green: 0.068, blue: 0.088)).preferredColorScheme(.dark)
        .sheet(isPresented: $model.showSetup) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Logitech setup", systemImage: "gearshape").font(.title2.bold())
                Text("OpenLogi connects your devices and owns saved profiles and mappings. NeroNook uses its agent connection for device status and temporary mouse adjustments.")
                LabeledContent("Application", value: model.preferences.application).font(.callout).textSelection(.enabled)
                LabeledContent("Last response", value: model.lastRead?.formatted() ?? "No response yet")
                Text(model.status).foregroundStyle(.secondary)
                Text("Keyboard backlight, Fn lock and host switching need an expanded OpenLogi integration. Those settings are not available in this version.").font(.callout)
                HStack {
                    Button("Choose OpenLogi…") { model.chooseApplication() }.disabled(model.busy)
                    Button("Open OpenLogi") { model.openOpenLogi() }
                    Spacer(); Button("Done") { model.showSetup = false }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 580)
        }
    }
}
