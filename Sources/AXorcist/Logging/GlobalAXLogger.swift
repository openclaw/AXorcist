import Foundation
import Logging

@MainActor
public class GlobalAXLogger {
    private init() {
        self.store = Self.sharedStore
        if ProcessInfo.processInfo.environment["AXORC_JSON_LOG_ENABLED"]?.lowercased() == "true" {
            self.isJSONLoggingEnabled = true
            self.emit("{\"axorc_log_stream_type\":\"json_objects\"," +
                "\"status\":\"AXGlobalLogger initialized with JSON output to stderr.\"}")
        }
    }

    init(store: AXLogStore) {
        self.store = store
    }

    public static let shared = GlobalAXLogger()
    public var isJSONLoggingEnabled = false
    public var isLoggingEnabled = false
    public var detailLevel: AXLogDetailLevel = .normal

    public func log(_ entry: AXLogEntry) {
        _ = self.store.enqueue(.entry(entry))
        self.drainPending()
    }

    public func getEntries() -> [AXLogEntry] {
        self.drainPending()
        return self.rawEntries
    }

    public func clearEntries() {
        _ = self.store.enqueue(.clear)
        self.drainPending()
    }

    public func getLogsAsStrings(format: AXLogOutputFormat = .text) -> [String] {
        self.drainPending()
        return self.store.getLogsAsStrings(format: format)
    }

    fileprivate nonisolated static let sharedStore = AXLogStore()

    fileprivate func drainPending() {
        guard !self.isDraining else { return }
        self.isDraining = true
        defer { self.isDraining = false }
        while true {
            let requests = self.store.takePending()
            guard !requests.isEmpty else { return }
            for request in requests {
                switch request {
                case let .message(message): self.process(message.entry)
                case let .entry(entry): self.process(entry)
                case .clear: self.clearProcessedEntries()
                }
            }
        }
    }

    private struct Key: Equatable {
        let message: String
        let level: AXLogLevel
    }

    private var rawEntries: [AXLogEntry] = []
    private let store: AXLogStore
    private var lastKey: Key?
    private var lastEntry: AXLogEntry?
    private var isDraining = false
    private var duplicateCount = 0

    private func process(_ entry: AXLogEntry) {
        guard self.shouldLog(entry.level) else { return }
        let messageLength = entry.message.count
        let message = messageLength > 300
            ? "\(entry.message.prefix(300))… (\(messageLength) chars)"
            : entry.message
        let key = Key(message: message, level: entry.level)
        if self.lastKey == key {
            self.lastEntry = entry
            self.duplicateCount += 1
            if self.duplicateCount.isMultiple(of: 5) {
                self.append(self.summary("⟳ Previous message repeated 5 more times", source: entry))
            }
            return
        }
        if self.duplicateCount >= 5, let previous = self.lastEntry {
            self.append(self.summary(
                "⟳ Previous message repeated \(self.duplicateCount) times in total", source: previous))
        }
        self.lastKey = key
        self.lastEntry = entry
        self.duplicateCount = 0
        self.append(AXLogEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            level: entry.level,
            message: message,
            file: entry.file,
            function: entry.function,
            line: entry.line,
            details: entry.details))
    }

    private func shouldLog(_ level: AXLogLevel) -> Bool {
        guard self.isLoggingEnabled else { return false }
        switch self.detailLevel {
        case .minimal: return level == .error || level == .critical
        case .normal: return level != .debug
        case .verbose: return true
        }
    }

    private func clearProcessedEntries() {
        self.lastKey = nil
        self.lastEntry = nil
        self.duplicateCount = 0
        self.rawEntries.removeAll()
        self.store.clearEntries()
    }

    private func summary(_ message: String, source: AXLogEntry) -> AXLogEntry {
        AXLogEntry(
            level: source.level,
            message: message,
            file: source.file,
            function: source.function,
            line: source.line)
    }

    private func append(_ entry: AXLogEntry) {
        // Read and encode AnyCodable payloads on their owning actor before publishing snapshots.
        let json = self.jsonString(for: entry)
        let snapshot = (try? JSONDecoder().decode(AXLogEntry.self, from: Data(json.utf8))) ?? AXLogEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            level: entry.level,
            message: entry.message,
            file: entry.file,
            function: entry.function,
            line: entry.line)
        self.rawEntries.append(entry)
        self.store.append(.init(entry: snapshot, text: entry.formattedForTextLog(), json: json))
        if self.isJSONLoggingEnabled {
            self.emit(json)
        }
    }

    private func jsonString(for entry: AXLogEntry) -> String {
        do {
            let data = try JSONEncoder().encode(entry)
            return String(data: data, encoding: .utf8) ?? "{\"error\":\"Invalid UTF-8 log output\"}"
        } catch {
            let message = "Failed to serialize log entry to JSON: \(error.localizedDescription)"
            let data = try? JSONEncoder().encode(["error": message])
            return data.flatMap { String(data: $0, encoding: .utf8) }
                ?? "{\"error\":\"Failed to serialize log entry to JSON\"}"
        }
    }

    private func emit(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

// MARK: - Logger Convenience Overloads

extension Logging.Logger {
    @inlinable
    public nonisolated func debug(_ message: @autoclosure () -> String) {
        self.log(level: .debug, "\(message())")
    }

    @inlinable
    public nonisolated func info(_ message: @autoclosure () -> String) {
        self.log(level: .info, "\(message())")
    }

    @inlinable
    public nonisolated func warning(_ message: @autoclosure () -> String) {
        self.log(level: .warning, "\(message())")
    }

    @inlinable
    public nonisolated func error(_ message: @autoclosure () -> String) {
        self.log(level: .error, "\(message())")
    }
}

public nonisolated func axDebugLog(
    _ message: String,
    details: [String: AnyCodable]? = nil,
    file: String = #file,
    function: String = #function,
    line: Int = #line)
{
    recordLog(level: .debug, message: message, details: details, source: (file: file, function: function, line: line))
}

public nonisolated func axInfoLog(
    _ message: String,
    details: [String: AnyCodable]? = nil,
    file: String = #file,
    function: String = #function,
    line: Int = #line)
{
    recordLog(level: .info, message: message, details: details, source: (file: file, function: function, line: line))
}

public nonisolated func axWarningLog(
    _ message: String,
    details: [String: AnyCodable]? = nil,
    file: String = #file,
    function: String = #function,
    line: Int = #line)
{
    recordLog(level: .warning, message: message, details: details, source: (file: file, function: function, line: line))
}

public nonisolated func axErrorLog(
    _ message: String,
    details: [String: AnyCodable]? = nil,
    file: String = #file,
    function: String = #function,
    line: Int = #line)
{
    recordLog(level: .error, message: message, details: details, source: (file: file, function: function, line: line))
}

public nonisolated func axFatalLog(
    _ message: String,
    details: [String: AnyCodable]? = nil,
    file: String = #file,
    function: String = #function,
    line: Int = #line)
{
    recordLog(
        level: .critical,
        message: message,
        details: details,
        source: (file: file, function: function, line: line))
}

private nonisolated func recordLog(
    level: AXLogLevel,
    message: String,
    details: [String: AnyCodable]?,
    source: (file: String, function: String, line: Int))
{
    enqueueLogRequest(.message(.init(
        level: level,
        message: message,
        details: details,
        file: source.file,
        function: source.function,
        line: source.line)))
}

public nonisolated func axGetLogEntries() -> [AXLogEntry] {
    GlobalAXLogger.sharedStore.getEntries()
}

public nonisolated func axClearLogs() {
    enqueueLogRequest(.clear)
}

public nonisolated func axGetLogsAsStrings(format: AXLogOutputFormat = .text) -> [String] {
    GlobalAXLogger.sharedStore.getLogsAsStrings(format: format)
}

private nonisolated func enqueueLogRequest(_ request: AXLogStore.Request) {
    if GlobalAXLogger.sharedStore.enqueue(request) {
        Task { @MainActor in GlobalAXLogger.shared.drainPending() }
    }
}
