import AXorcist

@MainActor
func executeLibraryCommand(
    command: CommandEnvelope,
    axorcist: AXorcist,
    traversalOptions: AXTraversalOptions) -> HandlerResponse
{
    guard let axCommand = command.command.toAXCommand(commandEnvelope: command) else {
        let name = command.command.rawValue.prefix(1).uppercased() + command.command.rawValue.dropFirst()
        axErrorLog("Failed to convert \(name) to AXCommand")
        return HandlerResponse(data: nil, error: "Internal error: Failed to create AXCommand for \(name)")
    }

    let response = axorcist.runCommand(
        AXCommandEnvelope(commandID: command.commandId, command: axCommand),
        traversalOptions: traversalOptions)
    return HandlerResponse(from: response)
}
