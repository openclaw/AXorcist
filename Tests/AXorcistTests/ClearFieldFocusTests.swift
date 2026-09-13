import ApplicationServices
import Testing
@testable import AXorcist

@Suite("Element clearing focus", .tags(.safe))
@MainActor
struct ClearFieldFocusTests {
    @Test
    func `failed focus does not dispatch clear input`() {
        let element = Element(AXUIElementCreateApplication(2_147_483_647))
        var dispatched = false
        #expect(throws: ElementTypingError.self) {
            try element.clearField(ensureFocus: { false }, performClear: { dispatched = true })
        }
        #expect(!dispatched)
    }

    @Test
    func `successful focus dispatches once`() throws {
        let element = Element(AXUIElementCreateApplication(2_147_483_647))
        var focusCalls = 0
        var clearCalls = 0
        try element.clearField(
            ensureFocus: { focusCalls += 1; return true },
            performClear: { clearCalls += 1 })
        #expect(focusCalls == 1)
        #expect(clearCalls == 1)
    }
}
