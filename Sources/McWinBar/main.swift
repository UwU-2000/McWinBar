import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: TaskbarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Raising other apps' windows and reserving space both need
        // Accessibility permission. Prompt once; the app still runs without it.
        WindowActivator.ensureAccessibility(prompt: true)
        // Hide the system Dock while our taskbar is the one in charge.
        DockHider.hide()
        controller = TaskbarController()
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
