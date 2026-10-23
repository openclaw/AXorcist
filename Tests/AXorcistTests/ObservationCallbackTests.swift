import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("Observation callback details", .serialized)
@MainActor
struct ObservationCallbackTests {
    @Test
    func `callback preserves complete changed details in text and JSON logs`() {
        let logger = GlobalAXLogger(store: AXLogStore())
        logger.isLoggingEnabled = true
        let element = AXUIElementCreateApplication(getpid())
        let prefix = String(repeating: "a", count: 400)
        var value = prefix + "ONE"
        let callback = AXorcist().makeObservationCallback(
            details: ["AXValue", "AXRole", "MissingAttribute"],
            logger: logger,
            readAttribute: { observed, name in
                #expect(CFEqual(observed.underlyingElement, element))
                switch name {
                case "AXValue": return value as CFString
                case "AXRole": return "AXTextField" as CFString
                default: return nil
                }
            })
        callback(getpid(), .valueChanged, element, nil)
        value = prefix + "TWO"
        callback(getpid(), .valueChanged, element, nil)
        callback(getpid(), .valueChanged, element, nil)

        let entries = logger.getEntries().filter { $0.message.hasPrefix("AXObserver CALLBACK:") }
        #expect(entries.count == 2)
        #expect(entries.map { $0.details?["AXValue"]?.value as? String } == [prefix + "ONE", prefix + "TWO"])
        #expect(entries.allSatisfy { $0.details?["AXRole"]?.value as? String == "AXTextField" })
        #expect(entries.allSatisfy { $0.details?["MissingAttribute"]?.value as? String == "nil" })
        for format in [AXLogOutputFormat.text, .json] {
            let logs = logger.getLogsAsStrings(format: format).joined(separator: "\n")
            #expect(logs.contains(prefix + "ONE"))
            #expect(logs.contains(prefix + "TWO"))
            #expect(logs.contains("AXTextField"))
        }
    }
}
