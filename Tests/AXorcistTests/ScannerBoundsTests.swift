import Testing
@testable import AXorcist

@Suite("Scanner bounds", .tags(.safe))
@MainActor
struct ScannerBoundsTests {
    @Test
    func `signed limits are representable`() {
        for expected in [Int.min, -1, 0, 1, Int.max] {
            let scanner = Scanner(string: String(expected))
            let actual: Int? = scanner.scanInteger()
            #expect(actual == expected)
            #expect(scanner.location == scanner.string.endIndex)
        }
        let scanner = Scanner(string: " \t+127 rest")
        let value: Int8? = scanner.scanInteger()
        #expect(value == 127)
        #expect(String(scanner.string[scanner.location...]) == " rest")
    }

    @Test
    func `failures restore the cursor`() {
        for input in ["128", "-129", "+", " -", " +x", String(repeating: "9", count: 10000)] {
            let scanner = Scanner(string: input)
            let value: Int8? = scanner.scanInteger()
            #expect(value == nil)
            #expect(scanner.location == scanner.string.startIndex)
        }
        for input in ["9223372036854775808", "-9223372036854775809"] {
            let scanner = Scanner(string: input)
            let value: Int? = scanner.scanInteger()
            #expect(value == nil)
            #expect(scanner.location == scanner.string.startIndex)
        }
    }

    @Test
    func `cursor advances by characters`() {
        let scanner = Scanner(string: "👩🏽‍💻12")
        #expect(scanner.scanCharacters(in: CustomCharacterSet(charactersInString: "👩🏽‍💻")) == "👩🏽‍💻")
        let value: Int? = scanner.scanInteger()
        #expect(value == 12)
        #expect(scanner.location == scanner.string.endIndex)
    }

    @Test
    func `floating point conversion preserves representable exponent extremes`() throws {
        for input in ["1e-320", "5e-324", "0e999", "-0e999", "1.7976931348623157e308", "1e-999999999999999999999"] {
            let expected = try #require(Double(input))
            let scanner = Scanner(string: input + " tail")
            let actual = try #require(scanner.scanDouble())
            #expect(actual == expected)
            #expect(actual.sign == expected.sign)
            #expect(String(scanner.string[scanner.location...]) == " tail")
        }
    }

    @Test
    func `floating point scanning keeps its boundaries`() {
        let fixtures: [(String, Double, String)] = [
            (".5 tail", 0.5, " tail"),
            ("-1.25e2", -125, ""),
            ("+1E-2", 0.01, ""),
            ("1.", 1, "."),
            ("1e+", 1, "e+"),
        ]
        for (input, expected, remaining) in fixtures {
            let scanner = Scanner(string: input)
            #expect(scanner.scanDouble() == expected)
            #expect(String(scanner.string[scanner.location...]) == remaining)
        }
    }
}
