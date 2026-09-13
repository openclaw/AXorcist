import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("Native value formatting", .tags(.safe))
@MainActor
struct NativeValueFormattingTests {
    @Test
    func `range uses its native payload`() throws {
        let value = try #require(AXValue.create(range: CFRange(location: 42, length: 7)))
        #expect(formatAXValue(value) == "<CFRange: pos=42 len=7>")
        #expect(formatAXValue(value, option: .raw) == "pos=42 len=7")
        #expect(formatCFTypeRef(value) == "<CFRange: pos=42 len=7>")
        #expect(value.cfRange()?.location == 42)
        #expect(value.cfRange()?.length == 7)
    }

    @Test
    func `geometry and error formatting stay typed`() throws {
        let point = try #require(AXValue.create(point: CGPoint(x: 1, y: 2)))
        let size = try #require(AXValue.create(size: CGSize(width: 3, height: 4)))
        let rect = try #require(AXValue.create(rect: CGRect(x: 1, y: 2, width: 3, height: 4)))
        let error = try #require(AXValue.create(error: .cannotComplete))
        #expect(formatAXValue(point) == "<CGPoint: x=1.0 y=2.0>")
        #expect(formatAXValue(size, option: .raw) == "w=3.0 h=4.0")
        #expect(formatAXValue(rect) == "<CGRect: x=1.0 y=2.0 w=3.0 h=4.0>")
        #expect(formatAXValue(error, option: .raw) == AXError.cannotComplete.stringValue)
    }

    @Test
    func `collection formatting contains values`() {
        #expect(formatCFTypeRef(["alpha", 2, true] as NSArray) == #"["alpha", 2, true]"#)
        #expect(formatCFTypeRef([] as NSArray) == "[]")
        #expect(formatCFTypeRef([1, 2, 3, 4, 5, 6] as NSArray, option: .raw) == "<Array of size 6>")
        let dictionary: NSDictionary = ["b": ["inside"], "a": 2]
        #expect(formatCFTypeRef(dictionary) == #"{"a": 2, "b": ["inside"]}"#)
    }

    @Test
    func `element formatting uses and escapes descriptions`() {
        #expect(formatElementValueDescription(role: "AXButton", title: "Save", option: .raw) == #"AXButton:"Save""#)
        #expect(formatElementValueDescription(role: "AXButton", title: "A\"B\n", option: .smart)
            == #"<AXButton: "A\"B\n">"#)
        #expect(formatElementValueDescription(role: "AXButton", title: nil, option: .smart) == "<AXButton>")
        #expect(formatElementValueDescription(role: "AXButton", title: "", option: .raw) == "AXButton")
        #expect(formatCFTypeRef(AXUIElementCreateApplication(2_147_483_647)) == "<Unknown>")
    }
}
