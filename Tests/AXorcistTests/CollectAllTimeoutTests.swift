import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("collectAll request timeout", .serialized)
@MainActor
struct CollectAllTimeoutTests {
    @Test
    func `collectAll stops at the request traversal timeout`() {
        let root = self.chain(prefix: 2_030_000_000)
        let clock = ScriptedClock([0, 0, 2])

        let count = self.collectedCount(
            from: root,
            timeout: 1,
            now: { clock.now() })

        #expect(count == 1)
    }

    @Test
    func `collectAll still walks the tree when the request timeout has not elapsed`() {
        let root = self.chain(prefix: 2_030_000_100)
        let clock = ScriptedClock([0, 0, 0.2, 0.4])

        let count = self.collectedCount(
            from: root,
            timeout: 30,
            now: { clock.now() })

        #expect(count == 3)
    }

    private func collectedCount(
        from root: Element,
        timeout: TimeInterval,
        now: @escaping AXTraversalClock) -> Int
    {
        let response = AXorcist().handleCollectAll(
            command: CollectAllCommand(
                appIdentifier: "fixture",
                attributesToReturn: [],
                maxDepth: 5),
            traversalOptions: AXTraversalOptions(
                timeout: timeout,
                scanAll: true,
                stopAtFirstMatch: false),
            applicationResolver: { _ in root },
            now: now)
        let payload = response.payload?.value as? [String: Any]
        return payload?["count"] as? Int ?? -1
    }

    private func chain(prefix: pid_t) -> Element {
        let grandchild = self.element(pid: prefix + 3, title: "grandchild")
        let child = self.element(pid: prefix + 2, title: "child", children: [grandchild])
        return self.element(pid: prefix + 1, title: "root", children: [child])
    }

    private func element(
        pid: pid_t,
        title: String,
        children: [Element] = []) -> Element
    {
        Element(
            AXUIElementCreateApplication(pid),
            attributes: [
                AXAttributeNames.kAXRoleAttribute: .string(AXRoleNames.kAXGroupRole),
                AXAttributeNames.kAXTitleAttribute: .string(title),
            ],
            children: children,
            actions: [])
    }
}

private final class ScriptedClock {
    private var instants: [TimeInterval]

    init(_ instants: [TimeInterval]) {
        self.instants = instants
    }

    func now() -> TimeInterval {
        guard !self.instants.isEmpty else { return 10000 }
        return self.instants.removeFirst()
    }
}
