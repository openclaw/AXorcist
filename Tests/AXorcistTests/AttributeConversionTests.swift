import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("Attribute conversion", .tags(.safe))
@MainActor
struct AttributeConversionTests {
    private let element = Element(AXUIElementCreateSystemWide())

    @Test(arguments: ["Synthetic sheet text", ""])
    func `Any attributes expose string payloads without optional boxes`(_ expected: String) throws {
        let actual: Any = try #require(self.element.convertCFTypeToSwiftType(
            expected as CFString,
            attribute: Attribute<Any>(AXAttributeNames.kAXValueAttribute)))

        #expect(actual as? String == expected)
        #expect(Mirror(reflecting: actual).displayStyle != .optional)
    }

    @Test
    func `AnyObject attributes bridge the payload rather than an optional`() throws {
        let actual: AnyObject = try #require(self.element.convertCFTypeToSwiftType(
            "Synthetic sheet text" as CFString,
            attribute: Attribute<AnyObject>(AXAttributeNames.kAXValueAttribute)))

        #expect(actual as? String == "Synthetic sheet text")
    }

    @Test
    func `Any attributes keep numbers and booleans distinct`() throws {
        let fixtures = [
            NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: -1), NSNumber(value: 1.25),
            NSNumber(value: UInt64.max),
            NSNumber(value: false), NSNumber(value: true),
        ]

        for expected in fixtures {
            let actual: Any = try #require(self.element.convertCFTypeToSwiftType(
                expected,
                attribute: Attribute<Any>(AXAttributeNames.kAXValueAttribute)))

            #expect(Mirror(reflecting: actual).displayStyle != .optional)
            let number = try #require(actual as? NSNumber)
            #expect(number == expected)
            #expect(CFGetTypeID(number) == CFGetTypeID(expected))
        }
    }

    @Test
    func `Any attributes unwrap native geometry and errors`() throws {
        let point = CGPoint(x: 1, y: 2)
        let size = CGSize(width: 3, height: 4)
        let rect = CGRect(origin: point, size: size)

        try self.expectPayload(point, from: #require(AXValue.create(point: point)))
        try self.expectPayload(size, from: #require(AXValue.create(size: size)))
        try self.expectPayload(rect, from: #require(AXValue.create(rect: rect)))
        try self.expectPayload(AXError.cannotComplete, from: #require(AXValue.create(error: .cannotComplete)))
    }

    @Test
    func `Any attributes unwrap native ranges`() throws {
        let value = try #require(AXValue.create(range: CFRange(location: 7, length: 11)))
        let actual: Any = try #require(self.element.convertCFTypeToSwiftType(
            value,
            attribute: Attribute<Any>(AXAttributeNames.kAXValueAttribute)))

        #expect(Mirror(reflecting: actual).displayStyle != .optional)
        let range = try #require(actual as? CFRange)
        #expect(range.location == 7)
        #expect(range.length == 11)
    }

    @Test
    func `Any attributes unwrap collections and preserve element identity`() throws {
        let array: Any = try #require(self.element.convertCFTypeToSwiftType(
            ["text", NSNumber(value: 2)] as NSArray,
            attribute: Attribute<Any>(AXAttributeNames.kAXValueAttribute)))
        #expect(Mirror(reflecting: array).displayStyle != .optional)
        let items = try #require(array as? [Any?])
        #expect(items.count == 2)
        #expect(items[0] as? String == "text")
        #expect(items[1] as? Int == 2)

        let expected = AXUIElementCreateApplication(2_000_000_123)
        let actual: Any = try #require(self.element.convertCFTypeToSwiftType(
            expected,
            attribute: Attribute<Any>(AXAttributeNames.kAXValueAttribute)))
        #expect(Mirror(reflecting: actual).displayStyle != .optional)
        #expect(CFGetTypeID(actual as CFTypeRef) == AXUIElementGetTypeID())
        #expect(CFEqual(actual as CFTypeRef, expected))
    }

    @Test
    func `Specific conversions and mismatched types retain their behavior`() throws {
        try self.expectPayload("text", from: "text" as CFString)
        try self.expectPayload(1, from: NSNumber(value: 1))
        try self.expectPayload(false, from: kCFBooleanFalse)

        let nativePoint = try #require(AXValue.create(point: .zero))
        let string: String? = self.element.convertCFTypeToSwiftType(
            nativePoint,
            attribute: .title)
        let point: CGPoint? = self.element.convertCFTypeToSwiftType(
            "not geometry" as CFString,
            attribute: Attribute<CGPoint>(AXAttributeNames.kAXValueAttribute))
        #expect(string == nil)
        #expect(point == nil)
        #expect(ValueUnwrapper.unwrap(nil) == nil)
    }

    @Test
    func `String attributes do not stringify non-text payloads`() throws {
        let values: [CFTypeRef] = try [
            NSNumber(value: 1), kCFBooleanTrue, NSNull(),
            ["text"] as NSArray, ["text": "value"] as NSDictionary,
            AXUIElementCreateApplication(2_000_000_123),
            #require(AXValue.create(range: CFRange(location: 1, length: 2))),
        ]
        for value in values {
            let actual: String? = self.element.convertCFTypeToSwiftType(
                value,
                attribute: Attribute<String>(AXAttributeNames.kAXValueAttribute))
            #expect(actual == nil)
        }
    }

    @Test
    func `Any attributes project attributed text and preserve null objects`() throws {
        try self.expectPayload("attributed text", from: NSAttributedString(string: "attributed text"))

        let actual: Any = try #require(self.element.convertCFTypeToSwiftType(
            NSNull(),
            attribute: Attribute<Any>(AXAttributeNames.kAXValueAttribute)))
        #expect(actual is NSNull)
        #expect(Mirror(reflecting: actual).displayStyle != .optional)
    }

    private func expectPayload<T: Equatable>(_ expected: T, from raw: CFTypeRef) throws {
        let typed: T? = self.element.convertCFTypeToSwiftType(
            raw,
            attribute: Attribute<T>(AXAttributeNames.kAXValueAttribute))
        let erased: Any = try #require(self.element.convertCFTypeToSwiftType(
            raw,
            attribute: Attribute<Any>(AXAttributeNames.kAXValueAttribute)))

        #expect(typed == expected)
        #expect(erased as? T == expected)
        #expect(Mirror(reflecting: erased).displayStyle != .optional)
    }
}
