import Foundation

final nonisolated class AXLogStore: @unchecked Sendable {
    struct Message: Sendable {
        let level: AXLogLevel
        let message: String
        // Producers retain AnyCodable's existing Sendable contract; only the main actor reads payloads.
        let details: [String: AnyCodable]?
        let file: String
        let function: String
        let line: Int

        @MainActor
        var entry: AXLogEntry {
            AXLogEntry(
                level: self.level,
                message: self.message,
                file: self.file,
                function: self.function,
                line: self.line,
                details: self.details)
        }
    }

    enum Request: Sendable {
        case message(Message)
        case entry(AXLogEntry)
        case clear
    }

    struct Record: Sendable {
        let entry: AXLogEntry
        let text: String
        let json: String
    }

    private let lock = NSLock()
    private var pending: [Request] = []
    private var drainScheduled = false
    private var records: [Record] = []

    func enqueue(_ request: Request) -> Bool {
        self.lock.withLock {
            self.pending.append(request)
            guard !self.drainScheduled else { return false }
            self.drainScheduled = true
            return true
        }
    }

    @MainActor
    func takePending() -> [Request] {
        self.lock.withLock {
            let requests = self.pending
            self.pending = []
            self.drainScheduled = false
            return requests
        }
    }

    @MainActor
    func append(_ record: Record) {
        self.lock.withLock { self.records.append(record) }
    }

    @MainActor
    func clearEntries() {
        let removed = self.lock.withLock {
            let records = self.records
            self.records = []
            return records
        }
        // Payload deinitializers may log; release their last references after unlocking.
        withExtendedLifetime(removed) {}
    }

    func getEntries() -> [AXLogEntry] {
        self.lock.withLock { self.records.map(\.entry) }
    }

    func getLogsAsStrings(format: AXLogOutputFormat) -> [String] {
        self.lock.withLock {
            switch format {
            case .text: self.records.map(\.text)
            case .json: self.records.map(\.json)
            }
        }
    }
}
