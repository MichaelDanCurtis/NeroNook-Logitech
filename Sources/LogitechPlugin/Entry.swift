import AppKit
@main struct Entry {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ModuleApp(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
