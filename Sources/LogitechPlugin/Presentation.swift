import SwiftUI
import NookPluginSDK

func mouseDiagram(dpi: Int?, wheel: String?, battery: String, connected: Bool) -> PluginDiagram {
    let accent = connected ? "#72E2C1" : "#8D99AB"
    var elements: [PluginDiagramElement] = [
        .init(.box, x: 0, y: 0, w: 640, h: 360, fill: "#11161E", radius: 18),
        .init(.text, x: 28, y: 20, w: 310, h: 25, fill: "#8D99AB", text: "YOUR MOUSE · YOUR WAY", font: 12),
        .init(.ellipse, x: 67, y: 307, w: 174, h: 13, fill: "#080B10"),
        .init(.box, x: 75, y: 68, w: 159, h: 239, fill: "#242D39", stroke: "#455164", radius: 70),
        .init(.box, x: 45, y: 164, w: 60, h: 126, fill: "#1C2531", radius: 28),
        .init(.line, x: 155, y: 80, w: 0, h: 106, stroke: "#0C1118", weight: 2),
        .init(.box, x: 144, y: 108, w: 22, h: 52, fill: accent, radius: 8),
        .init(.box, x: 148, y: 180, w: 14, h: 18, fill: "#0C1118", radius: 6),
        .init(.box, x: 61, y: 159, w: 12, h: 35, fill: "#5E6E83", radius: 5),
        .init(.text, x: 73, y: 327, w: 186, h: 18, fill: "#8D99AB", text: "Powered by OpenLogi", font: 11),
        .init(.box, x: 285, y: 66, w: 325, h: 106, fill: "#1B2330", radius: 14),
        .init(.text, x: 309, y: 82, w: 255, h: 18, fill: "#8D99AB", text: "POINTER SPEED", font: 11),
        .init(.text, x: 308, y: 110, w: 250, h: 40, fill: accent, text: dpi.map { "\($0) DPI" } ?? "Unavailable", font: 32),
        .init(.box, x: 285, y: 185, w: 325, h: 82, fill: "#1B2330", radius: 14),
        .init(.text, x: 309, y: 199, w: 250, h: 18, fill: "#8D99AB", text: "SMARTSHIFT WHEEL", font: 11),
        .init(.text, x: 309, y: 226, w: 250, h: 26, fill: "#ECF3FC", text: wheel == "Ratchet" ? "Tactile scrolling" : wheel == "Free" ? "Free spinning" : "Unavailable", font: 22),
        .init(.text, x: 306, y: 291, w: 260, h: 20, fill: "#8D99AB", text: "\(connected ? "Battery" : "Last known battery") · \(battery)", font: 14)
    ]
    for y in stride(from: 118.0, through: 148.0, by: 6) { elements.append(.init(.line, x: 148, y: y, w: 14, h: 0, stroke: "#1D594F", weight: 1)) }
    return .init(id: "mouse", title: "Mouse overview", width: 640, height: 360, summary: "\(dpi.map { "\($0) DPI" } ?? "DPI unavailable"). Wheel \(wheel ?? "unavailable"). Battery \(battery).", elements: elements)
}
struct SettingsView: View {
    @ObservedObject var model: ModuleApp
    @State private var chosenDPI = 2000
    @State private var chosenMode = "ratchet"
    @State private var threshold = 20
    private let mint = Color(red: 0.45, green: 0.89, blue: 0.76)
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "computermouse.fill").font(.system(size: 36)).foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mouse controls").font(.title.bold())
                    Text(model.selected?.name ?? "Logitech + OpenLogi").foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.battery).font(.title2.monospacedDigit()).foregroundStyle(mint)
            }
            HStack {
                Circle().fill(model.ready ? mint : .orange).frame(width: 7, height: 7)
                Text(model.status).font(.caption).lineLimit(2)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy)
            }
            Picker("Mouse", selection: Binding(get: { model.preferences.device }, set: { model.selectDevice($0) })) {
                if model.inventory?.mice.contains(where: { $0.id == model.preferences.device }) != true { Text("Select a connected mouse").tag(model.preferences.device) }
                ForEach(model.inventory?.mice ?? []) { device in Text(device.name + (device.online ? "" : " · offline")).tag(device.id) }
            }.disabled(model.busy)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Pointer speed").font(.headline); Spacer()
                    Text(model.dpi.map { "Current · \($0.current) DPI" } ?? "Unavailable").foregroundStyle(.secondary).font(.caption)
                }
                HStack(spacing: 8) {
                    ForEach([800, 1200, 1600, 2000, 3200], id: \.self) { value in
                        Button("\(value)") { chosenDPI = value }.tint(chosenDPI == value ? mint : .gray)
                            .disabled(model.dpi?.capabilities.values.contains(value) != true)
                    }
                }
                HStack {
                    Picker("DPI", selection: $chosenDPI) {
                        if model.dpi?.capabilities.values.contains(chosenDPI) != true { Text("\(chosenDPI)").tag(chosenDPI) }
                        ForEach(model.dpi?.capabilities.values ?? [], id: \.self) { Text("\($0)").tag($0) }
                    }.frame(width: 200)
                    Spacer()
                    Button("Apply DPI") { model.applyDPI(chosenDPI) }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                        .disabled(!model.ready || model.dpi?.capabilities.values.contains(chosenDPI) != true || model.busy)
                }
            }.padding(16).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Scroll wheel").font(.headline); Spacer(); Text(model.wheel?.mode == "Free" ? "Free spinning" : model.wheel?.mode == "Ratchet" ? "Tactile" : "Unavailable").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Picker("Mode", selection: $chosenMode) { Text("Tactile").tag("ratchet"); Text("Free spin").tag("free") }.pickerStyle(.segmented)
                    Button("Apply mode") { model.applyWheel(mode: chosenMode, threshold: nil) }
                }
                HStack {
                    Stepper("Sensitivity · \(threshold == 255 ? "Always tactile" : String(threshold))", value: $threshold, in: 1...255)
                    Spacer()
                    Button("Apply sensitivity") { model.applyWheel(mode: nil, threshold: threshold) }
                }
                Text("Mode and sensitivity apply separately. Wheel torque stays untouched.").font(.caption).foregroundStyle(.secondary)
            }.padding(16).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                .disabled(!model.ready || model.wheel == nil || model.busy)
            Text(model.notice.isEmpty ? "Changes are temporary. OpenLogi's saved profiles may reapply their settings." : model.notice).font(.caption).foregroundStyle(model.notice.isEmpty ? .secondary : .primary).lineLimit(3).frame(minHeight: 32, alignment: .topLeading)
            Spacer(minLength: 0)
            HStack {
                Button("Choose OpenLogi…") { model.chooseApplication() }.disabled(model.busy)
                Button("Profiles & buttons ↗") { model.openOpenLogi() }
                Spacer()
                Text("Logitech module · 0.1.1").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(24).frame(width: 640, height: 590).background(Color(red: 0.065, green: 0.083, blue: 0.115)).preferredColorScheme(.dark)
            .onChange(of: model.dpi?.current) { _, value in if let value { chosenDPI = value } }
            .onChange(of: model.wheel?.mode) { _, value in if let value { chosenMode = value.lowercased() } }
            .onChange(of: model.wheel?.autoDisengage) { _, value in if let value { threshold = value } }
            .onAppear { if let dpi = model.dpi { chosenDPI = dpi.current }; if let wheel = model.wheel { chosenMode = wheel.mode.lowercased(); threshold = wheel.autoDisengage } }
    }
}
