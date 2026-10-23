import AXorcist
import Foundation

@MainActor
func waitForObservation(owner: AXorcist) async throws {
    defer { owner.stopObserving() }
    while true {
        try await Task.sleep(for: .seconds(3600))
    }
}
