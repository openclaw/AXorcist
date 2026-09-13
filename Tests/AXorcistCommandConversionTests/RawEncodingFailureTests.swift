import Foundation
import Testing
@testable import axorc
@testable import AXorcist

@Suite("Raw response encoding failures")
@MainActor
struct RawEncodingFailureTests {
    @Test
    func `arbitrary command identifiers remain valid JSON`() throws {
        for identifier in ["quoted\"identifier", "line\nslash\\end", "☃"] {
            let response = finalizeAndEncodeResponse(
                commandId: identifier,
                commandType: "query",
                handlerResponse: HandlerResponse(data: AnyCodable(Double.nan)),
                debugCLI: false,
                commandDebugLogging: false)
            let object = try JSONDecoder().decode([String: String].self, from: Data(response.utf8))
            #expect(object["commandId"] == identifier)
            #expect(object["error"] == "JSON encoding failed")
        }
    }
}
