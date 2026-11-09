import Carbon.HIToolbox
import Foundation

/// Carbon 全局热键：不需要辅助功能权限。
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private let identity = UInt32.random(in: 1...UInt32.max)

    private(set) var isRegistered = false

    init(spec: HotKeySpec, action: @escaping () -> Void) {
        self.action = action
        installHandlerIfNeeded()
        isRegistered = register(spec)
    }

    deinit {
        if let reference {
            UnregisterEventHotKey(reference)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    @discardableResult
    func reload(spec: HotKeySpec) -> Bool {
        unregister()
        isRegistered = register(spec)
        return isRegistered
    }

    private func unregister() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
        isRegistered = false
    }

    private func register(_ spec: HotKeySpec) -> Bool {
        let hotKeyID = EventHotKeyID(signature: OSType(0x54464C50), id: identity) // 'TFLP'
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        return status == noErr
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard result == noErr else { return noErr }
            let instance = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            if hotKeyID.id == instance.identity {
                instance.action?()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, userData, &handlerRef)
    }
}
