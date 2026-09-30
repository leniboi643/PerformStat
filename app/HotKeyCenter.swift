import Foundation
import Carbon.HIToolbox

/// System-wide F3 hotkey (Carbon RegisterEventHotKey — no accessibility permission needed).
/// Toggles the overlay visibility; mirrors the menu bar show/hide action.
enum HotKeyCenter {
    nonisolated(unsafe) private static var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private static var onToggle: (() -> Void)?

    static func install(toggle: @escaping () -> Void) {
        onToggle = toggle

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // c-function handler: may only touch static/global state
        let handler: EventHandlerUPP = { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKeyCenter.onToggle?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)

        // F3, no modifiers. note: when "use F1/F2 as standard function keys" is off,
        // the hardware F3 key emits the mission-control media event instead and the
        // system consumes it before us — the menu item still works in that mode.
        let status = RegisterEventHotKey(
            UInt32(kVK_F3),
            UInt32(0),
            EventHotKeyID(signature: OSType(0x5053_5443) /* 'PSTC' */, id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("performstat: F3 hotkey registration failed: \(status)")
        }
    }
}
