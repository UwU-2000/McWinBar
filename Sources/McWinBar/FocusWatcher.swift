import AppKit
import ApplicationServices

/// Fires a callback the moment keyboard focus moves to a different window,
/// including switches between windows of the same app — which NSWorkspace
/// notifications don't cover. Works by keeping an AXObserver attached to the
/// frontmost app, re-attaching whenever the frontmost app changes.
final class FocusWatcher {
    private var observer: AXObserver?
    private var observedPid: pid_t = 0
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        attach(to: NSWorkspace.shared.frontmostApplication)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detach()
    }

    @objc private func frontAppChanged(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        attach(to: app ?? NSWorkspace.shared.frontmostApplication)
    }

    private func detach() {
        if let obs = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observer = nil
        observedPid = 0
    }

    private func attach(to app: NSRunningApplication?) {
        guard let app = app else { return }
        let pid = app.processIdentifier
        if pid == observedPid { return }
        detach()

        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon = refcon else { return }
            Unmanaged<FocusWatcher>.fromOpaque(refcon)
                .takeUnretainedValue().onChange()
        }
        guard AXObserverCreate(pid, callback, &obs) == .success,
              let observer = obs else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedWindowChangedNotification,
                     kAXMainWindowChangedNotification] {
            AXObserverAddNotification(observer, appElement, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        observedPid = pid
    }
}
