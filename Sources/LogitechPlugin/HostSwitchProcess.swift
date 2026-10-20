import Foundation
import LogitechCore

/// One owned, resident agent-only CLI stream. Never opens HID or replays input.
final class HostSwitchProcess: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Logitech.host-switch-stream")
    private var process: Process?
    private var stdout: Pipe?
    private var stderr: Pipe?
    private var bytes = Data()
    private var cursor: UInt64 = 0
    private var ready = false
    func start(executable: URL, device: String, choice: @escaping @Sendable (HostSwitchChoice) -> Void, status: @escaping @Sendable (String, Bool) -> Void) throws {
        let child = Process(), out = Pipe(), err = Pipe()
        child.executableURL = executable; child.arguments = ["api", "watch-host-switch", "--device", device]
        child.standardOutput = out; child.standardError = err
        process = child; stdout = out; stderr = err
        out.fileHandleForReading.readabilityHandler = { [weak self] file in
            let data = file.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.bytes.append(data)
                guard self.bytes.count <= 32768 else { status("Keyboard stream exceeded its limit; stopped.", false); if child.isRunning { child.terminate() }; return }
                while let end = self.bytes.firstIndex(of: 10) {
                    let line = self.bytes.prefix(upTo: end); self.bytes.removeSubrange(...end)
                    guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], json["schema_version"] as? Int == 1, json["ok"] as? Bool == true,
                          let body = json["data"] as? [String: Any], body["device"] as? String == device else { self.ready = false; status("OpenLogi host stream became unavailable; stopped.", false); if child.isRunning { child.terminate() }; return }
                    if body["type"] as? String == "baseline" { self.ready = true; status("Waiting for an Easy-Switch press", true); continue }
                    guard self.ready, let event = try? HostSwitchChoice(line: Data(line), expectedDevice: device, after: self.cursor, now: Date().timeIntervalSince1970) else { continue }
                    self.cursor = event.sequence; choice(event)
                }
            }
        }
        // Drain bounded diagnostics without retaining device identities or raw traffic.
        err.fileHandleForReading.readabilityHandler = { file in _ = file.availableData }
        child.terminationHandler = { _ in status("OpenLogi host stream stopped. Nothing was queued or replayed.", false) }
        try child.run()
    }
    func stop() {
        stdout?.fileHandleForReading.readabilityHandler = nil; stderr?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; stdout = nil; stderr = nil
    }
    deinit { stop() }
}
