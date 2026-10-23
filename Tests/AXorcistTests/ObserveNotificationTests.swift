import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("observe requested notifications")
@MainActor
struct ObserveNotificationTests {
    @Test
    func `observe subscribes every requested notification`() {
        let registry = NotificationListRegistry()
        let target = Element(AXUIElementCreateApplication(getpid()))
        let axorcist = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in (target, nil) })
        let response = axorcist.handleObserve(command: self.command(
            notifications: [
                AXNotification.valueChanged.rawValue,
                AXNotification.focusedUIElementChanged.rawValue,
            ]))

        #expect(response.status == "success")
        #expect(registry.notifications == [.valueChanged, .focusedUIElementChanged])
        #expect(registry.activeCount == 2)

        axorcist.stopObserving()
        #expect(registry.activeCount == 0)
    }

    @Test(arguments: [[], [AXNotification.valueChanged.rawValue, "NotANotification"]])
    func `observe rejects invalid notifications before subscribing`(notifications: [String]) {
        let registry = NotificationListRegistry()
        var resolved = false
        let axorcist = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in
                resolved = true
                return (nil, "should not resolve")
            })

        let response = axorcist.handleObserve(command: self.command(notifications: notifications))

        #expect(response.status == "error")
        #expect(response.error?.code == .invalidParameter)
        #expect(registry.notifications.isEmpty)
        #expect(resolved == false)
    }

    @Test
    func `observe rolls back earlier subscriptions when a later notification fails`() {
        let registry = NotificationListRegistry(failing: [.focusedUIElementChanged])
        let target = Element(AXUIElementCreateApplication(getpid()))
        let axorcist = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in (target, nil) })

        let response = axorcist.handleObserve(command: self.command(
            notifications: [
                AXNotification.valueChanged.rawValue,
                AXNotification.focusedUIElementChanged.rawValue,
            ]))

        #expect(response.status == "error")
        #expect(response.error?.code == .observationFailed)
        #expect(registry.notifications == [.valueChanged, .focusedUIElementChanged])
        #expect(registry.activeCount == 0)
    }

    @Test
    func `observer center dispatches each notification and stops the complete list`() throws {
        var registered: [AXNotification] = []
        var cleaned: [AXNotification] = []
        var received: [AXNotification] = []
        let center = AXObserverCenter(
            observerSetup: { _, _, notification in
                registered.append(notification)
                return .success
            },
            observerCleanup: { _, _, notification in cleaned.append(notification) })
        let target = Element(AXUIElementCreateApplication(getpid()))
        let axorcist = AXorcist(
            observationRegistry: center,
            observationTargetResolver: { _, _, _ in (target, nil) })
        let notifications: [AXNotification] = [.valueChanged, .focusedUIElementChanged]

        try axorcist.subscribeToNotifications(element: target, notifications: notifications) { _, name, _, _ in
            received.append(name)
        }.get()
        for notification in notifications {
            center.processNotification(
                pid: getpid(),
                notification: notification,
                rawElement: target.underlyingElement,
                nsUserInfo: nil)
        }
        #expect(registered == notifications)
        #expect(received == notifications)

        axorcist.stopObserving()
        #expect(center.registeredKeys.isEmpty)
        #expect(Set(cleaned) == Set(notifications))
        center.processNotification(
            pid: getpid(),
            notification: .valueChanged,
            rawElement: target.underlyingElement,
            nsUserInfo: nil)
        #expect(received == notifications)
    }

    @Test
    func `rollback preserves preexisting shared registrations`() throws {
        var cleaned: [AXNotification] = []
        var received = 0
        let center = AXObserverCenter(
            observerSetup: { _, _, notification in
                notification == .focusedUIElementChanged ? .notificationUnsupported : .success
            },
            observerCleanup: { _, _, notification in cleaned.append(notification) })
        let target = Element(AXUIElementCreateApplication(getpid()))
        let existing = try center.subscribe(pid: getpid(), element: target, notification: .valueChanged) { _, _, _, _ in
            received += 1
        }.get()
        let axorcist = AXorcist(
            observationRegistry: center,
            observationTargetResolver: { _, _, _ in (target, nil) })
        let response = axorcist.handleObserve(command: self.command(notifications: [
            AXNotification.valueChanged.rawValue,
            AXNotification.titleChanged.rawValue,
            AXNotification.focusedUIElementChanged.rawValue,
        ]))

        #expect(response.error?.code == .observationFailed)
        #expect(cleaned == [.titleChanged])
        #expect(center.registeredKeys.count == 1)
        axorcist.stopObserving()
        center.processNotification(
            pid: getpid(),
            notification: .valueChanged,
            rawElement: target.underlyingElement,
            nsUserInfo: nil)
        #expect(received == 1)
        try center.unsubscribe(token: existing)
        #expect(center.registeredKeys.isEmpty)
        #expect(cleaned == [.titleChanged, .valueChanged])
    }

    @Test
    func `observe subscribes direct children when watch children is set`() {
        let registry = NotificationListRegistry()
        let target = Element(AXUIElementCreateApplication(getpid()))
        let child = Element(AXUIElementCreateApplication(pid_t(1)))
        let axorcist = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in (target, nil) },
            observationChildProvider: { element in
                CFEqual(element.underlyingElement, target.underlyingElement) ? [child] : []
            })

        let response = axorcist.handleObserve(command: self.command(
            notifications: [AXNotification.valueChanged.rawValue],
            watchChildren: true,
            maxDepthForSearch: 1))

        #expect(response.status == "success")
        #expect(registry.notifications == [.valueChanged, .valueChanged])
        #expect(Set(registry.elements) == Set([target, child]))
        axorcist.stopObserving()
        #expect(registry.activeCount == 0)
    }

    @Test
    func `observe does not walk children unless watch children is set`() {
        let registry = NotificationListRegistry()
        let target = Element(AXUIElementCreateApplication(getpid()))
        let walked = ChildWalkFlag()
        let axorcist = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in (target, nil) },
            observationChildProvider: { _ in
                walked.called = true
                return []
            })

        let response = axorcist.handleObserve(command: self.command(
            notifications: [AXNotification.valueChanged.rawValue]))

        #expect(response.status == "success")
        #expect(walked.called == false)
        #expect(registry.elements.count == 1)
        axorcist.stopObserving()
    }

    @Test
    func `observe depth zero keeps the subscription on the requested element`() {
        let registry = NotificationListRegistry()
        let target = Element(AXUIElementCreateApplication(getpid()))
        let walked = ChildWalkFlag()
        let axorcist = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in (target, nil) },
            observationChildProvider: { _ in
                walked.called = true
                return [Element(AXUIElementCreateApplication(pid_t(1)))]
            })

        let response = axorcist.handleObserve(command: self.command(
            notifications: [AXNotification.valueChanged.rawValue],
            watchChildren: true,
            maxDepthForSearch: 0))

        #expect(response.status == "success")
        #expect(walked.called == false)
        #expect(registry.elements.count == 1)
        axorcist.stopObserving()
    }

    @Test
    func `observe stops the child walk at the traversal deadline`() {
        let registry = NotificationListRegistry()
        let target = Element(AXUIElementCreateApplication(getpid()))
        let walked = ChildWalkFlag()
        let clock = TraversalClock(times: [0, 100])
        let axorcist = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in (target, nil) },
            observationChildProvider: { _ in
                walked.called = true
                return [Element(AXUIElementCreateApplication(pid_t(1)))]
            })

        let response = axorcist.handleObserve(
            command: self.command(
                notifications: [AXNotification.valueChanged.rawValue],
                watchChildren: true,
                maxDepthForSearch: 5),
            traversalOptions: AXTraversalOptions(timeout: 1),
            now: { clock.next() })

        #expect(response.status == "success")
        #expect(walked.called == false)
        #expect(registry.elements.count == 1)
        axorcist.stopObserving()
    }

    @Test
    func `observe rolls back the parent when a child subscription fails`() {
        let registry = NotificationListRegistry(failAfter: 1)
        let target = Element(AXUIElementCreateApplication(getpid()))
        let child = Element(AXUIElementCreateApplication(pid_t(1)))
        let axorcist = AXorcist(
            observationRegistry: registry,
            observationTargetResolver: { _, _, _ in (target, nil) },
            observationChildProvider: { element in
                CFEqual(element.underlyingElement, target.underlyingElement) ? [child] : []
            })

        let response = axorcist.handleObserve(command: self.command(
            notifications: [AXNotification.valueChanged.rawValue],
            watchChildren: true,
            maxDepthForSearch: 1))

        #expect(response.status == "error")
        #expect(response.error?.code == .observationFailed)
        #expect(registry.activeCount == 0)
    }

    private func command(
        notifications: [String],
        watchChildren: Bool = false,
        includeElementDetails: [String]? = nil,
        maxDepthForSearch: Int = 10) -> ObserveCommand
    {
        ObserveCommand(
            appIdentifier: "fixture",
            notifications: notifications,
            watchChildren: watchChildren,
            notificationName: .valueChanged,
            includeElementDetails: includeElementDetails,
            maxDepthForSearch: maxDepthForSearch)
    }
}

@MainActor
private final class ChildWalkFlag {
    var called = false
}

@MainActor
private final class TraversalClock {
    private var times: [TimeInterval]

    init(times: [TimeInterval]) {
        self.times = times
    }

    func next() -> TimeInterval {
        guard !self.times.isEmpty else { return 100 }
        return self.times.removeFirst()
    }
}

@MainActor
private final class NotificationListRegistry: AXObservationRegistry {
    private var tokens: [SubscriptionToken: AXNotification] = [:]
    private let failing: Set<AXNotification>
    private let failAfter: Int?
    private var successCount = 0
    private(set) var notifications: [AXNotification] = []
    private(set) var elements: [Element] = []

    init(failing: Set<AXNotification> = [], failAfter: Int? = nil) {
        self.failing = failing
        self.failAfter = failAfter
    }

    var activeCount: Int {
        self.tokens.count
    }

    func subscribeProcess(
        pid _: pid_t,
        element: Element?,
        notification: AXNotification,
        handler _: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
    {
        self.notifications.append(notification)
        guard !self.failing.contains(notification) else {
            return .failure(.observerSetupFailed(details: "Fixture rejected \(notification.rawValue)"))
        }
        if let failAfter = self.failAfter, self.successCount >= failAfter {
            return .failure(.observerSetupFailed(details: "Fixture rejected subscription \(self.successCount)"))
        }
        let token = SubscriptionToken(id: UUID())
        self.tokens[token] = notification
        if let element {
            self.elements.append(element)
        }
        self.successCount += 1
        return .success(token)
    }

    func unsubscribe(token: SubscriptionToken) throws {
        guard self.tokens.removeValue(forKey: token) != nil else {
            throw AccessibilityError.tokenNotFound(tokenId: token.id)
        }
    }
}
