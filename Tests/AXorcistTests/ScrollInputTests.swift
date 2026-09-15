import CoreGraphics
import Testing
@testable import AXorcist

@Suite("Scroll input validation", .tags(.safe))
@MainActor
struct ScrollInputTests {
    @Test
    func `nonfinite or overflowing deltas throw before posting`() {
        let invalid: [Double] = [
            .nan, .infinity, -.infinity, .greatestFiniteMagnitude,
            (Double(Int32.max) + 1) * 10, (Double(Int32.min) - 1) * 10,
            Double(Int32.max) * 10, Double(Int32.min) * 10,
            (Double(Int16.max) + 1) * 10, (Double(Int16.min) - 1) * 10,
        ]
        for delta in invalid {
            #expect(throws: (any Error).self) { try InputDriver.scroll(deltaY: delta) }
            #expect(throws: (any Error).self) { try InputDriver.scroll(deltaX: delta, deltaY: 0) }
        }
    }

    @Test
    func `out of range pixel amounts throw before posting`() {
        for amount in [
            Int.min, Int.max, Int(Int32.min) - 1, Int(Int32.max) + 1,
            Int(Int32.min), Int(Int32.max), Int(Int16.min) - 1, Int(Int16.max) + 1,
        ] {
            #expect(throws: (any Error).self) {
                try Element.scrollAt(.zero, direction: .up, amount: amount)
            }
        }
    }

    @Test
    func `negative smooth amounts throw before constructing a range`() {
        for amount in [-1, Int.min] {
            #expect(throws: (any Error).self) {
                try Element.scrollAt(.zero, direction: .up, amount: amount, smooth: true)
            }
        }
    }

    @Test
    func `line events preserve truncation signed bounds and location`() throws {
        let point = CGPoint(x: 12, y: 34)
        for (input, expected) in [
            (29.9, Int32(2)), (-29.9, Int32(-2)), (9.9, Int32(0)),
            ((Double(Int16.max) + 0.75) * 10, Int32(Int16.max)),
            ((Double(Int16.min) - 0.75) * 10, Int32(Int16.min)),
        ] {
            let event = try InputDriver.scrollEvent(deltaX: input, deltaY: input, at: point)
            #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == Int64(expected))
            #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == Int64(expected))
            #expect(event.location == point)
        }
    }

    @Test
    func `pixel events preserve signed amounts on each axis`() throws {
        let point = CGPoint(x: 12, y: 34)
        for amount in [-Int(Int16.max), -3, 0, 3, Int(Int16.max)] {
            for direction in [ScrollDirection.up, .down, .left, .right] {
                let event = try Element.scrollEvent(at: point, direction: direction, amount: amount)
                let vertical = direction == .up || direction == .down
                let delta = direction == .down || direction == .right ? -Int64(amount) : Int64(amount)
                #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == (vertical ? delta : 0))
                #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == (vertical ? 0 : delta))
                #expect(event.location == point)
            }
        }
        let event = try Element.scrollEvent(at: point, direction: .up, amount: Int(Int16.min))
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == Int64(Int16.min))
        #expect(throws: (any Error).self) {
            try Element.scrollEvent(at: point, direction: .down, amount: Int(Int16.min))
        }
    }

    @Test
    func `zero smooth count remains a no-op`() throws {
        try Element.scrollAt(.zero, direction: .down, amount: 0, smooth: true)
    }
}
