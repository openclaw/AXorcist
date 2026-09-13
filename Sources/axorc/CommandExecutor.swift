// CommandExecutor.swift - Main command executor that coordinates command processing

import AppKit // For NSRunningApplication
import AXorcist
import Foundation

@MainActor
struct CommandExecutor {
    // MARK: Internal

    @MainActor
    static func execute(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool,
        traversalOptions: AXTraversalOptions = .standard) -> String
    {
        // The main AXORCCommand.run() now sets the global logging based on --debug.
        // CommandExecutor.setupLogging can adjust detail level if command.debugLogging is true.
        let previousDetailLevel = self.setupDetailLevelForCommand(
            commandDebugLogging: command.debugLogging,
            cliDebug: debugCLI)

        defer {
            // Restore only the detail level if it was changed.
            if let prevLevel = previousDetailLevel {
                GlobalAXLogger.shared.detailLevel = prevLevel
            }
        }

        axDebugLog(
            "Executing command: \(command.command) (ID: \(command.commandId)), "
                + "cmdDebug: \(command.debugLogging), cliDebug: \(debugCLI)")

        return self.processCommand(
            command: command,
            axorcist: axorcist,
            debugCLI: debugCLI,
            traversalOptions: traversalOptions)
    }

    static func stopObservations(axorcist: AXorcist) {
        axorcist.stopObserving()
    }

    // MARK: Private

    private static func setupDetailLevelForCommand(commandDebugLogging: Bool, cliDebug: Bool) -> AXLogDetailLevel? {
        // CLI --debug owns global logging; a command can request more detail within it.
        guard cliDebug, commandDebugLogging, GlobalAXLogger.shared.detailLevel != .verbose else { return nil }
        let previousDetailLevel = GlobalAXLogger.shared.detailLevel
        GlobalAXLogger.shared.detailLevel = .verbose
        axDebugLog("[CommandExecutor.setupDetailLevel] Upped detail level to verbose for this command.")
        return previousDetailLevel
    }

    private typealias DirectCommandHandler = @MainActor (
        CommandEnvelope,
        AXorcist,
        Bool,
        AXTraversalOptions) -> String
    private static let simpleCommands: Set<CommandType> = [
        .getFocusedElement,
        .getAttributes,
        .query,
        .describeElement,
        .extractText,
        .getElementAtPoint,
        .setFocusedValue,
        .observe,
    ]

    private static let commandHandlers: [CommandType: DirectCommandHandler] = [
        .performAction: handlePerformActionCommand,
        .collectAll: handleCollectAllCommand,
        .ping: { command, _, debugCLI, _ in handlePingCommand(command: command, debugCLI: debugCLI) },
        .batch: handleBatchCommand,
        .stopObservation: { command, axorcist, debugCLI, _ in
            handleStopObservationCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)
        },
        .isProcessTrusted: { command, _, _, _ in handleIsProcessTrustedCommand(command: command) },
        .isAXFeatureEnabled: { command, _, _, _ in handleIsAXFeatureEnabledCommand(command: command) },
    ]

    private static let notImplementedCommands: Set<CommandType> = [
        .setNotificationHandler,
        .removeNotificationHandler,
        .getElementDescription,
    ]

    @MainActor
    private static func processCommand(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool,
        traversalOptions: AXTraversalOptions) -> String
    {
        if self.simpleCommands.contains(command.command) {
            return handleSimpleCommand(
                command: command,
                axorcist: axorcist,
                debugCLI: debugCLI,
                traversalOptions: traversalOptions)
        }

        if let handler = commandHandlers[command.command] {
            return handler(command, axorcist, debugCLI, traversalOptions)
        }

        if self.notImplementedCommands.contains(command.command) {
            return handleNotImplementedCommand(
                command: command,
                message: "\(command.command.rawValue) is not implemented in axorc",
                debugCLI: debugCLI)
        }

        axErrorLog("Unhandled command: \(command.command.rawValue)")
        return "{\"error\": \"Unhandled command \(command.command.rawValue)\", \"commandId\": \"\(command.commandId)\"}"
    }

    @MainActor
    private static func handleCollectAllCommand(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool,
        traversalOptions: AXTraversalOptions) -> String
    {
        axDebugLog("CollectAll called. debugCLI=\(debugCLI). Passing to axorcist.handleCollectAll.")
        guard let axCommand = command.command.toAXCommand(commandEnvelope: command) else {
            axErrorLog("Failed to convert CollectAll to AXCommand")
            let errorResponse = HandlerResponse(
                data: nil,
                error: "Internal error: Failed to create AXCommand for CollectAll")
            return finalizeAndEncodeResponse(
                commandId: command.commandId,
                commandType: command.command.rawValue,
                handlerResponse: errorResponse,
                debugCLI: debugCLI,
                commandDebugLogging: command.debugLogging)
        }
        let axResponse = axorcist.runCommand(
            AXCommandEnvelope(commandID: command.commandId, command: axCommand),
            traversalOptions: traversalOptions)
        let handlerResponse = if axResponse.status == "success" {
            HandlerResponse(data: axResponse.payload, error: nil)
        } else {
            HandlerResponse(data: nil, error: axResponse.error?.message ?? "CollectAll failed")
        }
        return finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: handlerResponse,
            debugCLI: debugCLI,
            commandDebugLogging: command.debugLogging)
    }

    @MainActor
    private static func handleStopObservationCommand(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool) -> String
    {
        self.stopObservations(axorcist: axorcist)
        let stopResponse = FinalResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            status: "success",
            data: AnyCodable("All observations stopped"),
            error: nil,
            errorCode: nil,
            debugLogs: debugCLI || command.debugLogging ? axGetLogsAsStrings() : nil)
        return encodeToJson(stopResponse) ??
            "{\"error\": \"Encoding stopObservation response failed\", \"commandId\": \"\(command.commandId)\"}"
    }

    @MainActor
    private static func handleIsProcessTrustedCommand(command: CommandEnvelope) -> String {
        let trustedResponse = ProcessTrustedResponse(
            commandId: command.commandId,
            status: "success",
            trusted: AXIsProcessTrusted())
        return encodeToJson(trustedResponse) ??
            "{\"error\": \"Encoding isProcessTrusted response failed\", \"commandId\": \"\(command.commandId)\"}"
    }

    @MainActor
    private static func handleIsAXFeatureEnabledCommand(command: CommandEnvelope) -> String {
        let axEnabled = AXIsProcessTrustedWithOptions(nil)
        let featureEnabledResponse = AXFeatureEnabledResponse(
            commandId: command.commandId,
            status: "success",
            enabled: axEnabled)
        return encodeToJson(featureEnabledResponse) ??
            "{\"error\": \"Encoding isAXFeatureEnabled response failed\", \"commandId\": \"\(command.commandId)\"}"
    }
}
