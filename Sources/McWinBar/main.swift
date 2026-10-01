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

    /// Auto-start on login. Re-registers on every launch unless already
    /// enabled: replacing the app bundle on rebuilds can make the background
    /// task manager silently drop the record (status becomes .notFound), so a
    /// register-once guard would never heal it.
    private func registerAsLoginItem() {
        let service = SMAppService.mainApp
        let status = service.status
        Diag.log("login item status at launch: \(status.rawValue)")
        switch status {
        case .enabled:
            return
        case .requiresApproval:
            Diag.log("login item awaiting approval in System Settings > Login Items")
            return
        default: // .notRegistered, .notFound
            do {
                try service.register()
                Diag.log("login item registered, status now \(service.status.rawValue)")
            } catch {
                Diag.log("login item registration failed: \(error)")
            }
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
