import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey via the Carbon Hot Key API. Unlike a global
/// NSEvent monitor, this consumes the key event and needs no Input-Monitoring
/// permission. The handler runs on the main thread.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: virtual key code (e.g. `kVK_Escape`).
    ///   - modifiers: Carbon modifier mask (e.g. `controlKey`).
    @discardableResult
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData = userData else { return noErr }
                Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef)
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x54424B31) /* 'TBK1' */, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref)
        guard registerStatus == noErr else { return nil }
    }

    deinit {
        if let ref = ref { UnregisterEventHotKey(ref) }
        if let handlerRef = handlerRef { RemoveEventHandler(handlerRef) }
    }
}
