import ApplicationServices
import Testing
@testable import AXorcist

@Suite("Hierarchy value formatting", .tags(.safe))
@MainActor
struct HierarchyFormattingTests {
    @Test
    func `prefetched children respect requested descriptions`() async {
        let child = Element(AXUIElementCreateApplication(getpid()))
        var root = Element(AXUIElementCreateApplication(2_147_483_647))
        root.prefetchedChildren = [child]
        #expect(child.briefDescription(option: .raw) != child.briefDescription(option: .smart))
        for option in [ValueFormatOption.raw, .smart, .stringified] {
            let (attributes, _) = await getElementAttributes(
                element: root,
                attributes: [AXAttributeNames.kAXChildrenAttribute],
                outputFormat: .jsonString,
                valueFormatOption: option)
            #expect(attributes[AXAttributeNames.kAXChildrenAttribute]
                == .array([.string(child.briefDescription(option: option))]))
        }
    }

    @Test
    func `text children respect requested descriptions`() async {
        let child = Element(AXUIElementCreateApplication(getpid()))
        var root = child
        root.prefetchedChildren = [child]
        let (attributes, _) = await getElementAttributes(
            element: root,
            attributes: [AXAttributeNames.kAXChildrenAttribute],
            outputFormat: .textContent,
            valueFormatOption: .smart)
        #expect(attributes[AXAttributeNames.kAXChildrenAttribute]
            == .string("[\(child.briefDescription(option: .smart))]"))
    }

    @Test
    func `parent and focus keep their text labels`() {
        let element = Element(AXUIElementCreateApplication(2_147_483_647))
        #expect(formatParentAttribute(nil, outputFormat: .jsonString, valueFormatOption: .smart) == .null)
        #expect(formatChildrenAttribute([], outputFormat: .jsonString, valueFormatOption: .smart) == .null)
        #expect(formatFocusedUIElementAttribute(nil, outputFormat: .jsonString, valueFormatOption: .smart) == .null)
        #expect(formatFocusedUIElementAttribute(element, outputFormat: .textContent, valueFormatOption: .smart)
            == .string("Focused: ?Role - ?Title"))
    }

    @Test
    func `native value text uses requested format`() throws {
        let point = try #require(AXValue.create(point: CGPoint(x: 1, y: 2)))
        #expect(formatRawCFValueForTextContent(point, valueFormatOption: .raw) == "x=1.0 y=2.0")
        #expect(formatRawCFValueForTextContent(point, valueFormatOption: .smart) == "<CGPoint: x=1.0 y=2.0>")
    }
}
