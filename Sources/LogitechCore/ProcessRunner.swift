import Foundation
import Darwin

public struct ProcessRunner: CommandRunner {
    public init() {}
    public func run(_ executable: URL, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try Self.execute(executable, arguments)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    static func failureAdvice(arguments: [String]) -> String {
        let write = arguments.contains { ["--set", "--mode", "--threshold"].contains($0) }
        return write ? "No retry was sent; the requested write may have taken effect. Refresh before retrying." : "This was a read-only request; no setting change was attempted."
    }
    private static func execute(_ exe: URL, _ args: [String]) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: exe.path) else { throw BridgeProblem("OpenLogi is not installed at the selected location. Choose its application in Settings.") }
        let advice = failureAdvice(arguments: args)
        let process = Process(), out = Pipe(), err = Pipe(), ended = DispatchSemaphore(value: 0)
        process.executableURL = exe; process.arguments = args
        process.standardOutput = out; process.standardError = err
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        let output = Capture(), errors = Capture(), readers = DispatchGroup()
        for (pipe, capture) in [(out, output), (err, errors)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave() }
                while let chunk = try? pipe.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
                    if !capture.append(chunk) { if process.isRunning { process.terminate() }; break }
                }
            }
        }
        let timedOut = ended.wait(timeout: .now() + 15) == .timedOut
        if timedOut || output.overflow || errors.overflow {
            if process.isRunning { process.terminate() }
            if ended.wait(timeout: .now() + 1) == .timedOut, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        guard readers.wait(timeout: .now() + 2) == .success else { throw BridgeProblem("OpenLogi did not close its response. \(advice)") }
        guard !timedOut, !output.overflow, !errors.overflow else { throw BridgeProblem("OpenLogi timed out or exceeded its response limit. \(advice)") }
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Connection failed"
            throw BridgeProblem(String(detail.prefix(380)))
        }
        return output.data
    }
}
private final class Capture: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var exceeded = false
    func append(_ chunk: Data) -> Bool { lock.lock(); defer { lock.unlock() }; guard bytes.count + chunk.count <= 262144 else { exceeded = true; return false }; bytes.append(chunk); return true }
    var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
    var overflow: Bool { lock.lock(); defer { lock.unlock() }; return exceeded }
}
