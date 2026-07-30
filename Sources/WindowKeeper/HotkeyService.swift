import AppKit
import Carbon.HIToolbox

/// Registers one global hotkey via Carbon RegisterEventHotKey — the standard
/// mechanism for menu-bar apps: no extra permissions, works while any app is
/// focused, and consumes the keystroke so the focused app never sees it.
final class HotkeyService {
    static let keyO = UInt32(kVK_ANSI_O)
    static let optionCommand = UInt32(optionKey | cmdKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    /// Fails (returning nil) only if Carbon refuses the registration —
    /// e.g. another app already owns the exact combo.
    init?(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) {
        self.onPress = onPress

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData)
                    .takeUnretainedValue()
                service.onPress()
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef)
        guard installStatus == noErr else {
            Log.shared.error("Hotkey handler install failed: \(installStatus)")
            return nil
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x574B4859), // 'WKHY'
                                     id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                 GetApplicationEventTarget(),
                                                 0, &hotKeyRef)
        guard registerStatus == noErr else {
            Log.shared.error("Hotkey registration failed: \(registerStatus)")
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
