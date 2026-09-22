import Foundation

/// Fully hides the macOS Dock by enabling auto-hide with an effectively
/// infinite reveal delay (the standard "never show the Dock" technique).
///
/// A detached guardian process watches our PID and restores the Dock if we die
/// for any reason — including Force Quit (SIGKILL) or a crash, where
/// `applicationWillTerminate` never runs.
enum DockHider {
    private static var guardian: Process?

    static func hide() {
        applyHidden()
        startGuardian()
    }

    static func restore() {
        stopGuardian()
        applyVisible()
    }

    // MARK: - Dock state

    private static func applyHidden() {
        defaultsWrite("autohide", "-bool", "true")
        defaultsWrite("autohide-delay", "-float", "1000")
        defaultsWrite("autohide-time-modifier", "-float", "0")
        // Stop icon bounce (e.g. an app requesting attention) animating the
        // hidden Dock; we surface that on our taskbar instead.
        defaultsWrite("no-bouncing", "-bool", "true")
        restartDock()
    }

    private static func applyVisible() {
        defaultsDelete("autohide-delay")
        defaultsDelete("autohide-time-modifier")
        defaultsDelete("no-bouncing")
        defaultsWrite("autohide", "-bool", "false")
        restartDock()
    }

    // MARK: - Guardian

    private static func startGuardian() {
        let pid = getpid()
        let restoreCmd =
            "defaults delete com.apple.dock autohide-delay >/dev/null 2>&1; " +
            "defaults delete com.apple.dock autohide-time-modifier >/dev/null 2>&1; " +
            "defaults write com.apple.dock autohide -bool false; " +
            "killall Dock"
        // Poll until our process is gone, then restore. As an orphaned child it
        // survives our death (Force Quit signals only the main app, not this).
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 1; done; \(restoreCmd)"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        guardian = p
    }

    private static func stopGuardian() {
        guardian?.terminate()
        guardian = nil
    }

    // MARK: - Helpers

    private static func defaultsWrite(_ key: String, _ type: String, _ value: String) {
        run("/usr/bin/defaults", ["write", "com.apple.dock", key, type, value])
    }

    private static func defaultsDelete(_ key: String) {
        run("/usr/bin/defaults", ["delete", "com.apple.dock", key])
    }

    private static func restartDock() {
        run("/usr/bin/killall", ["Dock"])
    }

    private static func run(_ launchPath: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
