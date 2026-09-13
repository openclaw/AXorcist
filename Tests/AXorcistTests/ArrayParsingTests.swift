import Testing
@testable import AXorcist

@Suite("Array parsing")
struct ArrayParsingTests {
    @Test(arguments: [
        ("", nil),
        (" \n ", nil),
        ("[]", []),
        ("[ ]", []),
        ("item", ["item"]),
        ("a, b", ["a", "b"]),
        ("[a, , b]", ["a", "b"]),
        ("a,,", ["a"]),
        (",", []),
        (#"["a,b", "", "c"]"#, ["a,b", "", "c"]),
        (#"[1, "two", null]"#, ["1", "two", "<null>"]),
    ] as [(String, [String]?)])
    func `preserves accepted formats`(input: String, expected: [String]?) {
        #expect(decodeExpectedArray(fromString: input) == expected)
    }
}
