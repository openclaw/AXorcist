import AppKit
import ApplicationServices
import Carbon.HIToolbox

// MARK: - Keyboard Operations

extension Element {
    /// Type text into this element
    @MainActor public func typeText(_ text: String, delay: TimeInterval = 0.005, clearFirst: Bool = false) throws {
        try self.typeText(
            text,
            delay: delay,
            clearFirst: clearFirst,
            ensureFocus: self.focusForTextInput,
            eventDispatcher: { text, delay, clearFirst in
                if clearFirst {
                    try Element.clearFocusedField()
                }
                try Element.typeText(text, delay: delay)
            })
    }

    @MainActor
    func typeText(
        _ text: String,
        delay: TimeInterval,
        clearFirst: Bool,
        ensureFocus: () -> Bool,
        eventDispatcher: (String, TimeInterval, Bool) throws -> Void) throws
    {
        try Self.performFocusedInput(ensureFocus: ensureFocus) {
            try eventDispatcher(text, delay, clearFirst)
        }
    }

    /// Clear the text field
    @MainActor public func clearField() throws {
        try self.clearField(
            ensureFocus: self.focusForTextInput,
            performClear: { try Element.clearFocusedField() })
    }

    @MainActor
    func clearField(ensureFocus: () -> Bool, performClear: () throws -> Void) throws {
        try Self.performFocusedInput(ensureFocus: ensureFocus, action: performClear)
    }

    @MainActor
    private func focusForTextInput() -> Bool {
        self.attribute(Attribute<Bool>.focused) == true ||
            self.setValue(true, forAttribute: Attribute<Bool>.focused.rawValue)
    }

    @MainActor
    private static func performFocusedInput(ensureFocus: () -> Bool, action: () throws -> Void) throws {
        guard ensureFocus() else { throw ElementTypingError.focusFailed }
        try action()
    }

    @MainActor
    private static func clearFocusedField() throws {
        try Element.performHotkey(keys: ["cmd", "a"])
        Thread.sleep(forTimeInterval: 0.05)
        try Element.typeKey(.delete)
    }

    /// Type text at current focus
    @MainActor public static func typeText(_ text: String, delay: TimeInterval = 0.005) throws {
        for character in text {
            if character == "\n" {
                try self.typeKey(.return)
            } else if character == "\t" {
                try self.typeKey(.tab)
            } else {
                try self.typeCharacter(character)
            }

            Thread.sleep(forTimeInterval: delay > 0 ? delay : 0.001)
        }
    }

    /// Type a single character
    @MainActor public static func typeCharacter(_ character: Character) throws {
        // Physical key events survive VM/headless launch paths that can silently drop Unicode-only events.
        // Resolve them through the active layout so the resulting text remains layout-independent.
        if let stroke = self.keyboardStroke(for: character) {
            try self.postKeyboardStroke(stroke)
            return
        }

        let events = try self.unicodeCharacterEvents(character)
        self.postTypingEvents(events)
    }

    static func keyboardStroke(for character: Character) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        guard
            let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let rawLayoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue()
        guard let layoutBytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(layoutBytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        return self.keyboardStroke(for: character) { keyCode, flags in
            self.translatedString(for: keyCode, flags: flags, layout: layout)
        }
    }

    static func keyboardStroke(
        for character: Character,
        translatingWith translate: (CGKeyCode, CGEventFlags) -> KeyboardTranslation?)
        -> (keyCode: CGKeyCode, flags: CGEventFlags)?
    {
        let expected = String(character)
        guard expected.unicodeScalars.count == 1,
              let scalar = expected.unicodeScalars.first,
              scalar.isASCII,
              (0x20...0x7E).contains(scalar.value)
        else {
            return nil
        }

        let modifierOptions: [CGEventFlags] = [
            [],
            .maskShift,
            .maskAlternate,
            .maskShift.union(.maskAlternate),
        ]

        for flags in modifierOptions {
            for keyCode in CGKeyCode(0)...CGKeyCode(127) {
                guard let translation = translate(keyCode, flags),
                      translation.deadKeyState == 0,
                      translation.text == expected
                else {
                    continue
                }
                return (keyCode, flags)
            }
        }

        return nil
    }

    private static func translatedString(
        for keyCode: CGKeyCode,
        flags: CGEventFlags,
        layout: UnsafePointer<UCKeyboardLayout>) -> KeyboardTranslation?
    {
        var carbonModifiers: UInt32 = 0
        if flags.contains(.maskShift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        if flags.contains(.maskAlternate) {
            carbonModifiers |= UInt32(optionKey)
        }

        var deadKeyState: UInt32 = 0
        var actualLength = 0
        var codeUnits = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            (carbonModifiers >> 8) & 0xFF,
            UInt32(LMGetKbdType()),
            OptionBits(0),
            &deadKeyState,
            codeUnits.count,
            &actualLength,
            &codeUnits)

        guard status == noErr else { return nil }
        return KeyboardTranslation(
            text: String(utf16CodeUnits: codeUnits, count: actualLength),
            deadKeyState: deadKeyState)
    }

    struct KeyboardTranslation {
        let text: String
        let deadKeyState: UInt32
    }

    private static func postKeyboardStroke(_ stroke: (keyCode: CGKeyCode, flags: CGEventFlags)) throws {
        let descriptors = self.typingEventDescriptors(keyCode: stroke.keyCode, modifiers: stroke.flags)
        let events = try self.keyboardEvents(for: descriptors)
        self.postTypingEvents(events)
    }

    static func unicodeCharacterEvents(
        _ character: Character,
        factory: @MainActor (KeyboardEventDescriptor) -> CGEvent? = Element.makeKeyboardEvent) throws -> [CGEvent]
    {
        let descriptors = self.typingEventDescriptors(keyCode: 0, modifiers: [])
        let events = try self.keyboardEvents(for: descriptors, factory: factory)
        let chars = Array(String(character).utf16)
        chars.withUnsafeBufferPointer { buffer in
            for event in events {
                event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: buffer.baseAddress!)
            }
        }
        return events
    }

    private static func postTypingEvents(_ events: [CGEvent]) {
        for (index, event) in events.enumerated() {
            event.post(tap: .cghidEventTap)
            if index == 0 {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
    }

    /// Type a special key
    @MainActor public static func typeKey(_ key: SpecialKey, modifiers: CGEventFlags = []) throws {
        guard let keyCode = key.keyCode else {
            throw UIAutomationError.unsupportedKey(key.rawValue)
        }

        try self.postKeyboardStroke((keyCode, modifiers))
    }

    /// Perform a hotkey combination
    @MainActor public static func performHotkey(keys: [String], holdDuration: TimeInterval = 0.1) throws {
        var modifiers: [HotkeyModifier] = []
        var mainKey: SpecialKey?

        // Parse keys
        for key in keys {
            switch key.lowercased() {
            case "cmd", "command":
                modifiers.append(HotkeyModifier(keyCode: 0x37, flag: .maskCommand))
            case "shift":
                modifiers.append(HotkeyModifier(keyCode: 0x38, flag: .maskShift))
            case "option", "opt", "alt":
                modifiers.append(HotkeyModifier(keyCode: 0x3A, flag: .maskAlternate))
            case "ctrl", "control":
                modifiers.append(HotkeyModifier(keyCode: 0x3B, flag: .maskControl))
            case "fn", "function":
                modifiers.append(HotkeyModifier(keyCode: nil, flag: .maskSecondaryFn))
            default:
                // Try to parse as special key
                if let special = SpecialKey(rawValue: key.lowercased()) {
                    mainKey = special
                } else if key.count == 1 {
                    // Single character key
                    let char = key.lowercased().first!
                    mainKey = SpecialKey(character: char)
                }
            }
        }

        // Must have a main key
        guard let key = mainKey else {
            throw UIAutomationError.invalidHotkey(keys.joined(separator: "+"))
        }

        guard let mainKeyCode = key.keyCode else {
            throw UIAutomationError.unsupportedKey(key.rawValue)
        }

        let descriptors = self.hotkeyEventDescriptors(modifiers: modifiers, mainKeyCode: mainKeyCode)
        // Build the complete sequence before posting anything. Event creation can fail; posting cannot.
        let events = try self.keyboardEvents(for: descriptors)

        for (descriptor, event) in zip(descriptors, events) {
            event.post(tap: .cghidEventTap)
            if descriptor.keyCode == mainKeyCode, descriptor.keyDown, holdDuration > 0 {
                Thread.sleep(forTimeInterval: holdDuration)
            }
        }
    }

    struct HotkeyModifier {
        let keyCode: CGKeyCode?
        let flag: CGEventFlags
    }

    struct KeyboardEventDescriptor: Equatable {
        let keyCode: CGKeyCode
        let keyDown: Bool
        let flags: CGEventFlags
    }

    static func typingEventDescriptors(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags) -> [KeyboardEventDescriptor]
    {
        [
            KeyboardEventDescriptor(keyCode: keyCode, keyDown: true, flags: modifiers),
            KeyboardEventDescriptor(keyCode: keyCode, keyDown: false, flags: []),
        ]
    }

    static func hotkeyEventDescriptors(
        modifiers: [HotkeyModifier],
        mainKeyCode: CGKeyCode) -> [KeyboardEventDescriptor]
    {
        var descriptors: [KeyboardEventDescriptor] = []
        var activeFlags: CGEventFlags = []

        for modifier in modifiers {
            activeFlags.insert(modifier.flag)
            if let keyCode = modifier.keyCode {
                descriptors.append(KeyboardEventDescriptor(keyCode: keyCode, keyDown: true, flags: activeFlags))
            }
        }

        descriptors.append(KeyboardEventDescriptor(keyCode: mainKeyCode, keyDown: true, flags: activeFlags))
        descriptors.append(KeyboardEventDescriptor(keyCode: mainKeyCode, keyDown: false, flags: activeFlags))

        for modifier in modifiers.reversed() {
            activeFlags.remove(modifier.flag)
            if let keyCode = modifier.keyCode {
                descriptors.append(KeyboardEventDescriptor(keyCode: keyCode, keyDown: false, flags: activeFlags))
            }
        }

        return descriptors
    }

    static func keyboardEvents(
        for descriptors: [KeyboardEventDescriptor],
        factory: @MainActor (KeyboardEventDescriptor) -> CGEvent? = Element.makeKeyboardEvent) throws -> [CGEvent]
    {
        try descriptors.map { descriptor in
            guard let event = factory(descriptor) else {
                throw UIAutomationError.failedToCreateEvent
            }
            event.flags = descriptor.flags
            return event
        }
    }

    static func makeKeyboardEvent(_ descriptor: KeyboardEventDescriptor) -> CGEvent? {
        CGEvent(
            keyboardEventSource: nil,
            virtualKey: descriptor.keyCode,
            keyDown: descriptor.keyDown)
    }
}
