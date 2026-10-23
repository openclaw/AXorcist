import ApplicationServices
import Testing
@testable import axorc
@testable import AXorcist

@Suite("CLI observation lifetime")
@MainActor
struct ObservationLifetimeTests {
    @Test
    func `waiting yields the main actor and cancellation stops owned observations`() async throws {
        let center = AXObserverCenter(
            observerSetup: { _, _, _ in .success },
            observerCleanup: { _, _, _ in })
        let target = Element(AXUIElementCreateApplication(getpid()))
        let owner = AXorcist(
            observationRegistry: center,
            observationTargetResolver: { _, _, _ in (target, nil) })
        try owner.subscribeToNotifications(element: target, notifications: [.valueChanged]) { _, _, _, _ in }.get()
        let task = Task { @MainActor in try await waitForObservation(owner: owner) }
        await Task.yield()
        #expect(center.registeredKeys.count == 1)
        task.cancel()
        do {
            try await task.value
            Issue.record("Observation wait should throw when cancelled")
        } catch is CancellationError {
            #expect(center.registeredKeys.isEmpty)
        }
    }
}
