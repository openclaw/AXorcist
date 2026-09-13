import Foundation

// MARK: - UI Automation Errors

public enum UIAutomationError: Error, LocalizedError {
    case failedToCreateEvent
    case elementNotEnabled
    case elementNotActionable(timeout: TimeInterval)
    case unsupportedKey(String)
    case invalidHotkey(String)
    case missingFrame

    public var errorDescription: String? {
        switch self {
        case .failedToCreateEvent:
            "Failed to create system event"
        case .elementNotEnabled:
            "Element is not enabled"
        case let .elementNotActionable(timeout):
            "Element did not become actionable within \(timeout) seconds"
        case let .unsupportedKey(key):
            "Unsupported key: \(key)"
        case let .invalidHotkey(keys):
            "Invalid hotkey combination: \(keys)"
        case .missingFrame:
            "Element has no frame attribute"
        }
    }
}

enum ElementTypingError: Error, LocalizedError {
    case focusFailed

    var errorDescription: String? {
        "Failed to focus element before typing"
    }
}
