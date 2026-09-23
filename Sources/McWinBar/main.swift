import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: TaskbarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Raising other apps' windows and reserving space both need
        // Accessibility permission. Prompt once; the app still runs without it.
        WindowActivator.ensureAccessibility(prompt: true)
        // Hide the system Dock while our taskbar is the one in charge.
        DockHider.hide()
        registerAsLoginItem()
        controller = TaskbarController()
    }

    /// Auto-start on login. Registers once; if the user later disables the
    /// entry in System Settings > General > Login Items, we respect that and
    /// don't re-register (status will be .notFound, not .notRegistered).
    private func registerAsLoginItem() {
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        do {
            try service.register()
        } catch {
            NSLog("Login item registration failed: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Put the Dock back the way we found it.
        DockHider.restore()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: no Dock icon, no menu bar, behaves like a background agent.
app.setActivationPolicy(.accessory)
app.run()
