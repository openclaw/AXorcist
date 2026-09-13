import Foundation
import Testing
@testable import AXorcist

@Suite("Published log history", .tags(.safe), .serialized)
@MainActor
struct LogStoreTests {
    @Test
    func `global readers receive published history`() async {
        let logger = GlobalAXLogger.shared
        let enabled = logger.isLoggingEnabled
        let json = logger.isJSONLoggingEnabled
        let detail = logger.detailLevel
        defer {
            logger.clearEntries()
            logger.isLoggingEnabled = enabled
            logger.isJSONLoggingEnabled = json
            logger.detailLevel = detail
        }
        logger.isLoggingEnabled = true
        logger.isJSONLoggingEnabled = false
        logger.detailLevel = .verbose
        let message = "worker-\(UUID())"
        await Task.detached { axInfoLog(message) }.value
        #expect(logger.getEntries().contains { $0.message == message })
        let found = await Task.detached {
            !axGetLogEntries().isEmpty && axGetLogsAsStrings().contains { $0.contains(message) }
        }.value
        #expect(found)
        #expect(axGetLogsAsStrings().contains { $0.contains(message) })
        axClearLogs()
        #expect(logger.getEntries().isEmpty)
    }

    @Test
    func `condensation preserves identity and timestamp`() throws {
        let store = self.makeLogger()
        let entry = AXLogEntry(level: .info, message: String(repeating: "x", count: 500))
        store.log(entry)
        let stored = try #require(store.getEntries().first)
        #expect(stored.id == entry.id)
        #expect(stored.timestamp == entry.timestamp)
        #expect(stored.message == String(repeating: "x", count: 300) + "… (500 chars)")
    }

    @Test
    func `clearing resets duplicate suppression`() {
        let store = self.makeLogger()
        let entry = AXLogEntry(level: .info, message: "repeat")
        store.log(entry)
        store.log(entry)
        #expect(store.getEntries().count == 1)
        store.clearEntries()
        store.log(entry)
        #expect(store.getEntries().count == 1)
    }

    @Test
    func `minimal level keeps only errors and critical messages`() {
        let store = self.makeLogger()
        store.detailLevel = .minimal
        for level in AXLogLevel.allCases {
            store.log(AXLogEntry(level: level, message: "same text"))
        }
        #expect(store.getEntries().map(\.level) == [.error, .critical])
        for _ in 0..<6 {
            store.log(AXLogEntry(level: .critical, message: "same text"))
        }
        #expect(store.getEntries().allSatisfy { $0.level == .error || $0.level == .critical })
    }

    @Test
    func `concurrent producers are drained in full`() async {
        let history = AXLogStore()
        let logger = GlobalAXLogger(store: history)
        logger.isLoggingEnabled = true
        await Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<64 {
                    group.addTask {
                        _ = history.enqueue(.message(.init(
                            level: .info,
                            message: "entry-\(index)",
                            details: nil,
                            file: #file,
                            function: #function,
                            line: #line)))
                    }
                }
            }
        }.value
        let entries = logger.getEntries()
        #expect(entries.count == 64)
        #expect(Set(entries.map(\.message)).count == 64)
        #expect(history.getEntries().count == 64)
    }

    @Test
    func `queued clear preserves following messages`() {
        let history = AXLogStore()
        let logger = GlobalAXLogger(store: history)
        logger.isLoggingEnabled = true
        for message in ["before", "after"] {
            if message == "after" {
                _ = history.enqueue(.clear)
            }
            _ = history.enqueue(.message(.init(
                level: .info,
                message: message,
                details: nil,
                file: #file,
                function: #function,
                line: #line)))
        }
        #expect(logger.getEntries().map(\.message) == ["after"])
    }

    @Test
    func `json snapshots and encoding failures are valid JSON`() throws {
        let store = self.makeLogger()
        let message = "a quoted \"message\"\nwith a newline"
        store.log(AXLogEntry(level: .info, message: message))
        let encoded = try #require(store.getLogsAsStrings(format: .json).first)
        let decoded = try JSONDecoder().decode(AXLogEntry.self, from: Data(encoded.utf8))
        #expect(decoded.message == message)
        store.log(AXLogEntry(level: .info, message: "unencodable", details: ["value": AnyCodable(NSLock())]))
        let failure = try #require(store.getLogsAsStrings(format: .json).last)
        let object = try JSONDecoder().decode([String: String].self, from: Data(failure.utf8))
        #expect(object["error"]?.contains("serialize") == true)
    }

    @Test
    func `summary keeps the repeated severity`() {
        let logger = self.makeLogger()
        for _ in 0..<7 {
            logger.log(AXLogEntry(level: .info, message: "repeated", file: "original.swift"))
        }
        logger.log(AXLogEntry(level: .critical, message: "different", file: "next.swift"))
        let summaries = logger.getEntries().filter { $0.message.hasPrefix("⟳") }
        #expect(summaries.count == 2)
        #expect(summaries.allSatisfy { $0.level == .info && $0.file == "original.swift" })
    }

    @Test
    func `encoding can enqueue another log`() {
        let logger = self.makeLogger()
        logger.log(AXLogEntry(
            level: .info,
            message: "outer",
            details: ["value": AnyCodable(LoggingPayload(logger: logger))]))
        #expect(logger.getEntries().map(\.message) == ["outer", "nested"])
    }

    private struct LoggingPayload: Encodable {
        let logger: GlobalAXLogger

        func encode(to encoder: any Encoder) throws {
            self.logger.log(AXLogEntry(level: .info, message: "nested"))
            var container = encoder.singleValueContainer()
            try container.encode("value")
        }
    }

    @Test
    func `published entries do not retain reference payloads`() throws {
        let history = AXLogStore()
        let logger = GlobalAXLogger(store: history)
        logger.isLoggingEnabled = true
        var payload: MutablePayload? = MutablePayload()
        weak let weakPayload = payload
        logger.log(AXLogEntry(level: .info, message: "payload", details: ["value": AnyCodable(payload)]))
        let snapshots = history.getEntries()
        payload?.value = "changed"
        let details = try #require(snapshots.first?.details?["value"]?.value as? [String: Any])
        #expect(details["value"] as? String == "original")
        payload = nil
        logger.clearEntries()
        withExtendedLifetime(snapshots) { #expect(weakPayload == nil) }
    }

    @Test
    func `unencodable details stay on the actor`() {
        let history = AXLogStore()
        let logger = GlobalAXLogger(store: history)
        logger.isLoggingEnabled = true
        logger.log(AXLogEntry(level: .info, message: "opaque", details: ["value": AnyCodable(NSLock())]))
        #expect(logger.getEntries().first?.details != nil)
        #expect(history.getEntries().first?.details == nil)
    }

    private final class MutablePayload: Encodable {
        var value = "original"
    }

    private func makeLogger() -> GlobalAXLogger {
        let logger = GlobalAXLogger(store: AXLogStore())
        logger.isLoggingEnabled = true
        logger.detailLevel = .verbose
        return logger
    }
}
