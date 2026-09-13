import Testing
@testable import axorc
@testable import AXorcist

@Suite("Batch conversion validation")
@MainActor
struct BatchConversionTests {
    @Test
    func `invalid children reject the whole batch`() {
        let valid = CommandEnvelope(commandId: "valid", command: .query, pid: 2_147_483_647)
        let invalid: [CommandEnvelope] = [
            .init(commandId: "action", command: .performAction),
            .init(commandId: "value", command: .setFocusedValue, actionValue: AnyCodable(1)),
            .init(commandId: "point", command: .getElementAtPoint),
            .init(commandId: "observe", command: .observe, notifications: []),
            .init(commandId: "unsupported", command: .ping),
        ]
        for child in invalid {
            let batch = CommandEnvelope(commandId: "batch", command: .batch, subCommands: [valid, child])
            #expect(batch.command.toAXCommand(commandEnvelope: batch) == nil)
        }
    }

    @Test
    func `invalid nested batch rejects its parent`() {
        let invalid = CommandEnvelope(commandId: "bad", command: .performAction)
        let nested = CommandEnvelope(commandId: "nested", command: .batch, subCommands: [invalid])
        let outer = CommandEnvelope(commandId: "outer", command: .batch, subCommands: [nested])
        #expect(outer.command.toAXCommand(commandEnvelope: outer) == nil)
    }

    @Test
    func `valid and empty batches keep their order`() {
        let children: [CommandEnvelope] = [
            .init(commandId: "first", command: .query),
            .init(commandId: "second", command: .getAttributes),
        ]
        for commands in [children, []] {
            let envelope = CommandEnvelope(commandId: "batch", command: .batch, subCommands: commands)
            guard case let .batch(batch)? = envelope.command.toAXCommand(commandEnvelope: envelope) else {
                Issue.record("Expected a converted batch")
                continue
            }
            #expect(batch.commands.map(\.commandID) == commands.map(\.commandId))
        }
    }
}
