import AppKit
import Foundation
import os

@MainActor
protocol AXGlobalApplicationMonitoring: AnyObject, Sendable {
    var runningProcessIdentifiers: [pid_t] { get }

    func start(
        onLaunch: @escaping @MainActor (pid_t) -> Void,
        onTermination: @escaping @MainActor (pid_t) -> Void)
    func stop()
}

/// Event-driven application lifecycle source for global AX notification fan-out.
///
/// Accessibility observers are process scoped. `NSWorkspace` supplies the native
/// lifecycle events needed to attach and detach those observers without polling.
@MainActor
final class AXWorkspaceApplicationMonitor: AXGlobalApplicationMonitoring {
    convenience init() {
        self.init(workspace: NSWorkspace.shared, runningApplications: \.runningApplications)
    }

    init<Workspace: NSObject>(
        workspace: Workspace,
        runningApplications: any KeyPath<Workspace, [NSRunningApplication]> & Sendable)
    {
        self.observeRunningApplications = { handler in
            workspace.observe(runningApplications, options: [.initial]) { workspace, _ in
                // Indexed KVO changes can contain only the changed entries. Capture the full
                // membership snapshot here, without reading any application metadata.
                handler(workspace[keyPath: runningApplications])
            }
        }
    }

    var runningProcessIdentifiers: [pid_t] {
        self.entriesByID.values.compactMap(\.pid)
    }

    /// Internal test seam for metadata work delivered to the main queue.
    var didReceivePID: ((pid_t) -> Void)?

    func start(
        onLaunch: @escaping @MainActor (pid_t) -> Void,
        onTermination: @escaping @MainActor (pid_t) -> Void)
    {
        guard self.sessionID == nil else { return }
        let sessionID = UUID()
        self.sessionID = sessionID
        self.onLaunch = onLaunch
        self.onTermination = onTermination
        self.runningApplicationsObservation = self.observeRunningApplications { [weak self] applications in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sessionID == sessionID else { return }
                self.reconcile(applications, sessionID: sessionID)
            }
        }
    }

    func stop() {
        self.sessionID = nil
        self.runningApplicationsObservation?.invalidate()
        self.runningApplicationsObservation = nil
        for entry in self.entriesByID.values {
            entry.request.cancel()
        }
        self.entriesByIdentity = [:]
        self.entriesByID = [:]
        self.onLaunch = nil
        self.onTermination = nil
    }

    private let observeRunningApplications:
        (@escaping @Sendable ([NSRunningApplication]) -> Void) -> NSKeyValueObservation
    private var sessionID: UUID?
    private var runningApplicationsObservation: NSKeyValueObservation?
    // Reuse one serial worker across sessions: a blocked read never creates replacement workers.
    private let metadataQueue = DispatchQueue(label: "AXorcist.workspace-application-metadata")
    private var entriesByIdentity: [ObjectIdentifier: ApplicationEntry] = [:]
    private var entriesByID: [UUID: ApplicationEntry] = [:]
    private var onLaunch: (@MainActor (pid_t) -> Void)?
    private var onTermination: (@MainActor (pid_t) -> Void)?

    private final class ApplicationEntry {
        // Retain every indexed wrapper; ObjectIdentifier is only valid during its lifetime.
        var applications: [NSRunningApplication]
        let request: AXApplicationMetadataRequest
        var pid: pid_t?

        init(application: NSRunningApplication, request: AXApplicationMetadataRequest) {
            self.applications = [application]
            self.request = request
        }
    }

    isolated deinit {
        for entry in self.entriesByID.values {
            entry.request.cancel()
        }
    }

    private func reconcile(_ runningApplications: [NSRunningApplication], sessionID: UUID) {
        // Process every complete snapshot in order, even when an earlier metadata read is blocked.
        // Membership removal invalidates its request before a late PID/readiness result can arrive.
        let currentEntries = self.matchApplications(runningApplications, sessionID: sessionID)
        let currentIDs = Set(currentEntries.values.map(\.request.id))
        let removedEntries = self.entriesByID.values.filter { !currentIDs.contains($0.request.id) }
        var terminations: [pid_t] = []
        for entry in removedEntries {
            self.entriesByID.removeValue(forKey: entry.request.id)
            entry.request.cancel()
            if let pid = entry.pid {
                terminations.append(pid)
            }
        }
        // Re-key to this snapshot, dropping old aliases before releasing their wrappers.
        let previousEntriesByIdentity = self.entriesByIdentity
        self.entriesByIdentity = [:]
        let wrappersByID = Dictionary(grouping: runningApplications) {
            currentEntries[ObjectIdentifier($0)]!.request.id
        }
        for (id, applications) in wrappersByID {
            self.entriesByID[id]?.applications = applications
        }
        self.entriesByIdentity = currentEntries
        for pid in terminations.sorted() {
            guard self.sessionID == sessionID else { return }
            self.onTermination?(pid)
        }
        for application in runningApplications {
            guard self.sessionID == sessionID else { return }
            let identity = ObjectIdentifier(application)
            guard let entry = currentEntries[identity] else { continue }
            // Every launch or quit invalidates AppKit's cached metadata for all wrappers, so re-reading
            // resolved wrappers would cost a LaunchServices lookup per application. A wrapper the entry
            // already held keeps its process and PID; new or equal-but-distinct wrappers are always read.
            // Readiness completes through its own observation, and membership removal delivers termination.
            if previousEntriesByIdentity[identity] === entry, entry.request.hasDeliveredPositivePID {
                continue
            }
            entry.request.refresh(application)
        }
    }

    private func matchApplications(
        _ applications: [NSRunningApplication],
        sessionID: UUID) -> [ObjectIdentifier: ApplicationEntry]
    {
        var current: [ObjectIdentifier: ApplicationEntry] = [:]
        for application in applications {
            let identity = ObjectIdentifier(application)
            current[identity] = self.entriesByIdentity[identity]
        }
        // AppKit can give every NSRunningApplication the same hash. Only unseen wrappers
        // need semantic equality; a normal launch costs one scan and a removal costs none.
        for application in applications where current[ObjectIdentifier(application)] == nil {
            let entry = self.entriesByID.values.first { $0.applications[0] == application }
                ?? self.makeEntry(for: application, sessionID: sessionID)
            current[ObjectIdentifier(application)] = entry
        }
        return current
    }

    private func makeEntry(for application: NSRunningApplication, sessionID: UUID) -> ApplicationEntry {
        let requestID = UUID()
        let request = AXApplicationMetadataRequest(id: requestID, queue: self.metadataQueue) { [weak self] event in
            guard let self, self.sessionID == sessionID,
                  let entry = self.entriesByID[requestID] else { return }
            self.receive(event, from: entry)
        }
        let entry = ApplicationEntry(application: application, request: request)
        self.entriesByID[requestID] = entry
        return entry
    }

    private func receive(_ event: AXApplicationMetadataRequest.Event, from entry: ApplicationEntry) {
        switch event {
        case let .pid(pid):
            self.didReceivePID?(pid)
            guard pid > 0 else {
                if let previous = entry.pid {
                    entry.pid = nil
                    self.onTermination?(previous)
                }
                return
            }
            let previous = entry.pid
            entry.pid = pid
            if previous == nil {
                self.onLaunch?(pid)
            }
        case .ready:
            guard let pid = entry.pid else { return }
            self.onLaunch?(pid)
        }
    }
}

/// AppKit documents NSRunningApplication as thread-safe and the SDK marks it Sendable.
/// Request state uses the lock; native calls always run outside it.
private final nonisolated class AXApplicationMetadataRequest: Sendable {
    enum Event: Sendable {
        case pid(pid_t)
        case ready
    }

    private struct State {
        var cancelled = false
        var readinessStarted = false
        var lastDeliveredPID: pid_t?
        var observation: ReadinessObservation?
    }

    private struct ReadinessObservation: Sendable {
        let id: UUID
        let application: NSRunningApplication
        let token: NSKeyValueObservation

        func invalidate() {
            // Foundation's token does not keep its target alive. Retain the exact wrapper
            // through unregistering, even if ARC ends the lease's lifetime at this call.
            withExtendedLifetime(self.application) {
                self.token.invalidate()
            }
        }
    }

    let id: UUID
    private let queue: DispatchQueue
    private let deliver: @MainActor @Sendable (Event) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        id: UUID,
        queue: DispatchQueue,
        deliver: @escaping @MainActor @Sendable (Event) -> Void)
    {
        self.id = id
        self.queue = queue
        self.deliver = deliver
    }

    func cancel() {
        let observation = self.state.withLock {
            $0.cancelled = true
            let observation = $0.observation
            $0.observation = nil
            return observation
        }
        // Invalidation can contend with KVO delivery; stop must never join native work.
        self.queue.async { observation?.invalidate() }
    }

    /// The wrapper's positive PID has been delivered; readiness completes through its own observation.
    var hasDeliveredPositivePID: Bool {
        self.state.withLock { !$0.cancelled && ($0.lastDeliveredPID ?? 0) > 0 }
    }

    func refresh(_ application: NSRunningApplication) {
        self.queue.async { [self] in
            guard !self.isCancelled else { return }
            let pid = application.processIdentifier
            let shouldDeliverPID = self.state.withLock {
                guard !$0.cancelled, pid <= 0 || $0.lastDeliveredPID != pid else { return false }
                $0.lastDeliveredPID = pid
                return true
            }
            guard !self.isCancelled else { return }
            if shouldDeliverPID {
                self.send(.pid(pid))
            }
            guard pid > 0 else {
                self.resetReadiness()
                return
            }
            let shouldObserve = self.state.withLock {
                guard !$0.cancelled, !$0.readinessStarted else { return false }
                $0.readinessStarted = true
                return true
            }
            if shouldObserve {
                self.observeReadiness(of: application)
            }
        }
    }

    private var isCancelled: Bool {
        self.state.withLock { $0.cancelled }
    }

    private func resetReadiness() {
        let observation = self.state.withLock {
            $0.readinessStarted = false
            let observation = $0.observation
            $0.observation = nil
            return observation
        }
        observation?.invalidate()
    }

    private func observeReadiness(of application: NSRunningApplication) {
        guard !application.isFinishedLaunching, !self.isCancelled else { return }
        let observationID = UUID()
        // Do not request .new: KVO would fetch readiness synchronously on the notifying thread.
        let token = application.observe(\.isFinishedLaunching, options: []) { [weak self] application, _ in
            guard let self else { return }
            self.queue.async { self.checkReadiness(of: application, observationID: observationID) }
        }
        let observation = ReadinessObservation(id: observationID, application: application, token: token)
        let installed = self.state.withLock {
            guard !$0.cancelled else { return false }
            $0.observation = observation
            return true
        }
        guard installed else {
            observation.invalidate()
            return
        }
        self.checkReadiness(of: application, observationID: observationID)
    }

    private func checkReadiness(of application: NSRunningApplication, observationID: UUID) {
        guard self.state.withLock({ !$0.cancelled && $0.observation?.id == observationID }),
              application.isFinishedLaunching else { return }
        let observation = self.state.withLock {
            guard !$0.cancelled, $0.observation?.id == observationID else { return nil as ReadinessObservation? }
            let observation = $0.observation
            $0.observation = nil
            return observation
        }
        guard let observation else { return }
        observation.invalidate()
        self.send(.ready)
    }

    private func send(_ event: Event) {
        DispatchQueue.main.async { [deliver] in deliver(event) }
    }
}
