import Carbon.HIToolbox

/// The global ⌃⌘J capture hotkey. Carbon's `RegisterEventHotKey` needs no Accessibility permission.
@MainActor
enum HotKey {
    private static var action: (() -> Void)?
    private static var ref: EventHotKeyRef?

    static func register(_ action: @escaping () -> Void) {
        self.action = action
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &spec, nil, nil)
        // ponytail: fixed ⌃⌘J and a silent failure if another app owns it; make it changeable in Settings when asked.
        RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(cmdKey | controlKey), EventHotKeyID(signature: 0x5341_524F, id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    fileprivate static func fire() { action?() }
}

/// A plain C callback: no captured context, so it hops to the main actor through the static.
private func hotKeyPressed(_: EventHandlerCallRef?, _: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    Task { @MainActor in HotKey.fire() }
    return noErr
}
