import Foundation
import Testing
@testable import AXorcist

@Suite("Foundation number preservation", .tags(.safe))
@MainActor
struct FoundationNumberTests {
    @Test
    func `boxed numbers keep their JSON types`() throws {
        let fixtures: [(NSNumber, AttributeValue, String)] = [
            (NSNumber(value: 0), .int(0), "0"),
            (NSNumber(value: 1), .int(1), "1"),
            (NSNumber(value: -1), .int(-1), "-1"),
            (NSNumber(value: 1.25), .double(1.25), "1.25"),
            (NSNumber(value: false), .bool(false), "false"),
            (NSNumber(value: true), .bool(true), "true"),
        ]
        for (source, expected, json) in fixtures {
            #expect(AttributeValue(from: source) == expected)
            #expect(try String(data: JSONEncoder().encode(AnyCodable(source)), encoding: .utf8) == json)
        }
    }

    @Test
    func `native swift primitives keep their types`() {
        #expect(AttributeValue(from: 0) == .int(0))
        #expect(AttributeValue(from: 1) == .int(1))
        #expect(AttributeValue(from: 1.0) == .double(1.0))
        #expect(AttributeValue(from: false) == .bool(false))
        #expect(AttributeValue(from: true) == .bool(true))
    }

    @Test
    func `unsigned values do not wrap negative`() throws {
        let value = NSNumber(value: UInt64.max)
        let encoded = try JSONEncoder().encode(AnyCodable(value))
        #expect(String(data: encoded, encoding: .utf8) == String(UInt64.max))
        #expect(try JSONDecoder().decode(AnyCodable.self, from: encoded).value as? UInt64 == UInt64.max)
        #expect(AttributeValue(from: value) == .double(Double(UInt64.max)))
        #expect(AttributeValue(from: NSNumber(value: Int.max)) == .int(Int.max))
        #expect(AttributeValue(from: NSNumber(value: Int.min)) == .int(Int.min))
    }

    @Test
    func `nested values distinguish booleans from numbers`() throws {
        let values: [Any] = [NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: false), NSNumber(value: true)]
        let expected: AttributeValue = .array([.int(0), .int(1), .bool(false), .bool(true)])
        #expect(AttributeValue(from: values) == expected)
        let encoded = try JSONEncoder().encode(AnyCodable(["values": values]))
        #expect(try JSONDecoder().decode([String: AttributeValue].self, from: encoded)["values"] == expected)
        #expect(AnyCodable(NSNumber(value: 0)) != AnyCodable(false))
        #expect(AnyCodable(true) != AnyCodable(NSNumber(value: 1)))
        #expect(AnyCodable([NSNumber(value: 1)]) != AnyCodable([true]))
        #expect(AnyCodable(["value": NSNumber(value: 0)]) != AnyCodable(["value": false]))
        #expect(AnyCodable(NSNumber(value: 1)) == AnyCodable(1))
    }
}
