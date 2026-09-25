import CoreGraphics
import Testing
@testable import AXorcist

@Suite("Keyboard event generation")
@MainActor
struct KeyboardEventGenerationTests {
    @Test(arguments: [
        CGEventFlags(),
        .maskShift,
        .maskAlternate,
        .maskShift.union(.maskAlternate),
        .maskCommand.union(.maskControl),
    ])
    func `typing pairs replace inherited flags and finish neutral`(modifiers: CGEventFlags) throws {
        let descriptors = Element.typingEventDescriptors(keyCode: 0x24, modifiers: modifiers)
        let events = try Element.keyboardEvents(for: descriptors, factory: Self.contaminatedEvent)

        #expect(descriptors == [
            .init(keyCode: 0x24, keyDown: true, flags: modifiers),
            .init(keyCode: 0x24, keyDown: false, flags: []),
        ])
        #expect(events.map(\.type) == [.keyDown, .keyUp])
        #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0x24, 0x24])
        #expect(events.map(\.flags) == [modifiers, []])
    }

    @Test(arguments: [Character("A"), Character("@")])
    func `layout modifiers apply only while the character key is down`(character: Character) throws {
        let stroke = try #require(Element.keyboardStroke(for: character) { keyCode, flags in
            switch (keyCode, flags) {
            case (0, .maskShift): Element.KeyboardTranslation(text: "A", deadKeyState: 0)
            case (37, .maskAlternate): Element.KeyboardTranslation(text: "@", deadKeyState: 0)
            default: nil
            }
        })
        let events = try Element.keyboardEvents(
            for: Element.typingEventDescriptors(keyCode: stroke.keyCode, modifiers: stroke.flags),
            factory: Self.contaminatedEvent)

        #expect(events.count == 2)
        #expect(events[0].flags == (character == "A" ? .maskShift : .maskAlternate))
        #expect(events[1].flags.isEmpty)
    }

    @Test(arguments: ["é", "🙂", "👨‍👩‍👦", "e\u{301}"])
    func `Unicode pairs retain every UTF16 unit without inherited modifiers`(text: String) throws {
        let events = try Element.unicodeCharacterEvents(Character(text), factory: Self.contaminatedEvent)

        #expect(events.map(\.type) == [.keyDown, .keyUp])
        #expect(events.map(\.flags) == [[], []])
        #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0, 0])
        #expect(events.map(Self.unicodeUnits) == [Array(text.utf16), Array(text.utf16)])
    }

    @Test(arguments: [1, 2])
    func `typing allocation failure returns no partial pair`(failedAllocation: Int) {
        let descriptors = Element.typingEventDescriptors(keyCode: 0, modifiers: .maskShift)
        var creationCount = 0
        var events: [CGEvent]?
        do {
            events = try Element.keyboardEvents(for: descriptors) { descriptor in
                creationCount += 1
                return creationCount == failedAllocation ? nil : Self.contaminatedEvent(descriptor)
            }
            Issue.record("Expected event creation to fail")
        } catch UIAutomationError.failedToCreateEvent {
            // No complete array is available for the posting caller.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(creationCount == failedAllocation)
        #expect(events == nil)
    }

    @Test(arguments: [1, 2])
    func `Unicode allocation failure returns no partial pair`(failedAllocation: Int) {
        var creationCount = 0
        var events: [CGEvent]?
        do {
            events = try Element.unicodeCharacterEvents("🙂") { descriptor in
                creationCount += 1
                return creationCount == failedAllocation ? nil : Self.contaminatedEvent(descriptor)
            }
            Issue.record("Expected event creation to fail")
        } catch UIAutomationError.failedToCreateEvent {
            // Unicode payload assignment cannot expose a partial pair either.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(creationCount == failedAllocation)
        #expect(events == nil)
    }

    @Test
    func `hotkey main key up retains modifiers until their physical releases`() throws {
        let descriptors = Element.hotkeyEventDescriptors(
            modifiers: [
                .init(keyCode: 0x37, flag: .maskCommand),
                .init(keyCode: 0x38, flag: .maskShift),
            ],
            mainKeyCode: 0)
        let held: CGEventFlags = [.maskCommand, .maskShift]
        #expect(descriptors == [
            .init(keyCode: 0x37, keyDown: true, flags: .maskCommand),
            .init(keyCode: 0x38, keyDown: true, flags: held),
            .init(keyCode: 0, keyDown: true, flags: held),
            .init(keyCode: 0, keyDown: false, flags: held),
            .init(keyCode: 0x38, keyDown: false, flags: .maskCommand),
            .init(keyCode: 0x37, keyDown: false, flags: []),
        ])
        let events = try Element.keyboardEvents(for: descriptors, factory: Self.contaminatedEvent)
        #expect(events.map(\.flags) == descriptors.map(\.flags))
    }

    private static func contaminatedEvent(_ descriptor: Element.KeyboardEventDescriptor) -> CGEvent? {
        let event = Element.makeKeyboardEvent(descriptor)
        event?.flags = [.maskCommand, .maskControl, .maskShift, .maskAlternate, .maskAlphaShift, .maskSecondaryFn]
        return event
    }

    private static func unicodeUnits(from event: CGEvent) -> [UniChar] {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        var buffer = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count,
            actualStringLength: &length,
            unicodeString: &buffer)
        return buffer
    }
}
