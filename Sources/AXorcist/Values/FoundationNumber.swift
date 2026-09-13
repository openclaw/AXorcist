import Foundation

nonisolated enum FoundationNumber: Encodable, Sendable {
    case boolean(Bool)
    case integer(Int)
    case unsigned(UInt64)
    case floating(Double)

    init?(boxed value: Any) {
        // Preserve native Swift values; NSNumber's 0/1 casts can otherwise turn numbers into Bool.
        guard type(of: value) is NSNumber.Type, let number = value as? NSNumber else { return nil }
        self.init(number)
    }

    init(_ number: NSNumber) {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            self = .boolean(number.boolValue)
        } else if let value = number as? Int {
            self = .integer(value)
        } else if let value = number as? UInt64 {
            self = .unsigned(value)
        } else {
            self = .floating(number.doubleValue)
        }
    }

    var attributeValue: AttributeValue {
        switch self {
        case let .boolean(value): .bool(value)
        case let .integer(value): .int(value)
        case let .unsigned(value): .double(Double(value))
        case let .floating(value): .double(value)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .boolean(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .unsigned(value): try container.encode(value)
        case let .floating(value): try container.encode(value)
        }
    }
}
