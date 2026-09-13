import AppKit
import ApplicationServices

// MARK: - Mouse Button Types

public enum MouseButton: String, Sendable {
    case left
    case right
    case middle
}

struct MouseButtonEventKinds: Equatable {
    let button: CGMouseButton
    let down: CGEventType
    let dragged: CGEventType
    let up: CGEventType
}

extension MouseButton {
    var eventKinds: MouseButtonEventKinds {
        switch self {
        case .left:
            MouseButtonEventKinds(
                button: .left,
                down: .leftMouseDown,
                dragged: .leftMouseDragged,
                up: .leftMouseUp)
        case .right:
            MouseButtonEventKinds(
                button: .right,
                down: .rightMouseDown,
                dragged: .rightMouseDragged,
                up: .rightMouseUp)
        case .middle:
            MouseButtonEventKinds(
                button: .center,
                down: .otherMouseDown,
                dragged: .otherMouseDragged,
                up: .otherMouseUp)
        }
    }
}

// MARK: - Click Operations

extension Element {
    /// Click on this element
    @MainActor public func click(button: MouseButton = .left, clickCount: Int = 1) throws {
        // Ensure element is actionable
        guard isEnabled() ?? true else {
            throw UIAutomationError.elementNotEnabled
        }

        // Get element center
        guard let frame = frame() else {
            throw UIAutomationError.missingFrame
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)

        // Perform click at center
        try Element.clickAt(center, button: button, clickCount: clickCount)
    }

    /// Click at a specific point on screen
    @MainActor public static func clickAt(_ point: CGPoint, button: MouseButton = .left, clickCount: Int = 1) throws {
        let clickPairs = try self.buildClickEventPairs(at: point, button: button, clickCount: clickCount)

        for (index, pair) in clickPairs.enumerated() {
            pair.down.post(tap: .cghidEventTap)

            // Small delay between down and up
            Thread.sleep(forTimeInterval: 0.01)

            pair.up.post(tap: .cghidEventTap)

            // Small delay between successive clicks (stay within the system double-click interval)
            if index < clickPairs.count - 1 {
                Thread.sleep(forTimeInterval: 0.03)
            }
        }
    }

    @MainActor
    static func buildClickEventPairs(
        at point: CGPoint,
        button: MouseButton,
        clickCount: Int) throws -> [(down: CGEvent, up: CGEvent)]
    {
        let clampedCount = max(1, clickCount)

        let eventKinds = button.eventKinds

        var pairs: [(down: CGEvent, up: CGEvent)] = []
        pairs.reserveCapacity(clampedCount)

        for clickIndex in 1...clampedCount {
            guard let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: eventKinds.down,
                mouseCursorPosition: point,
                mouseButton: eventKinds.button)
            else {
                throw UIAutomationError.failedToCreateEvent
            }

            guard let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: eventKinds.up,
                mouseCursorPosition: point,
                mouseButton: eventKinds.button)
            else {
                throw UIAutomationError.failedToCreateEvent
            }

            // For a double click, the system expects a sequence of click states:
            // (1) down/up with clickState=1, then (2) down/up with clickState=2.
            let clickState = Int64(clickIndex)
            mouseDown.setIntegerValueField(.mouseEventClickState, value: clickState)
            mouseUp.setIntegerValueField(.mouseEventClickState, value: clickState)

            pairs.append((down: mouseDown, up: mouseUp))
        }

        return pairs
    }

    /// Wait for this element to become actionable
    @MainActor public func waitUntilActionable(
        timeout: TimeInterval = 5.0,
        pollInterval: TimeInterval = 0.1) async throws -> Element
    {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            // Check if element is actionable
            if self.isActionable() {
                return self
            }

            // Wait before next check
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        throw UIAutomationError.elementNotActionable(timeout: timeout)
    }

    /// Check if element is actionable (enabled, visible, on screen)
    @MainActor public func isActionable() -> Bool {
        // Must be enabled
        guard isEnabled() ?? true else { return false }

        // Must have a frame
        guard let frame = frame() else { return false }

        // Must be on screen
        guard frame.width > 0, frame.height > 0 else { return false }

        // Check if on any screen
        return NSScreen.screens.contains { screen in
            screen.frame.intersects(frame)
        }
    }
}

// MARK: - Scroll Operations

// swiftlint:disable identifier_name
public enum ScrollDirection: String, Sendable {
    case up
    case down
    case left
    case right
}

// swiftlint:enable identifier_name

extension Element {
    /// Scroll this element in a specific direction
    @MainActor public func scroll(direction: ScrollDirection, amount: Int = 3, smooth: Bool = false) throws {
        // Get element bounds for scroll location
        guard let frame = frame() else {
            throw UIAutomationError.missingFrame
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)

        // Perform scroll at element center
        try Element.scrollAt(center, direction: direction, amount: amount, smooth: smooth)
    }

    /// Scroll at a specific point
    @MainActor public static func scrollAt(
        _ point: CGPoint,
        direction: ScrollDirection,
        amount: Int = 3,
        smooth: Bool = false) throws
    {
        let scrollAmount = smooth ? 1 : amount
        let iterations = smooth ? amount : 1
        let delay = smooth ? 0.01 : 0.05

        for _ in 0..<iterations {
            // Create scroll event
            guard let scrollEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: direction == .up || direction == .down ? Int32(scrollAmount) : 0,
                wheel2: direction == .left || direction == .right ? Int32(scrollAmount) : 0,
                wheel3: 0)
            else {
                throw UIAutomationError.failedToCreateEvent
            }

            // Set scroll direction
            switch direction {
            case .up:
                scrollEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(scrollAmount))
            case .down:
                scrollEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -Int64(scrollAmount))
            case .left:
                scrollEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(scrollAmount))
            case .right:
                scrollEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -Int64(scrollAmount))
            }

            // Set location
            scrollEvent.location = point

            // Post event
            scrollEvent.post(tap: .cghidEventTap)

            // Delay between scrolls
            if iterations > 1 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
    }
}
