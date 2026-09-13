import ApplicationServices

@MainActor
public func formatAXValue(_ axValue: AXValue, option: ValueFormatOption = .smart) -> String {
    let type = axValue.valueType
    let name: String
    let contents: String?

    // Typed accessors keep native payload storage aligned with its AXValueType.
    switch type {
    case .cgPoint:
        name = "CGPoint"
        contents = axValue.cgPoint().map { "x=\($0.x) y=\($0.y)" }
    case .cgSize:
        name = "CGSize"
        contents = axValue.cgSize().map { "w=\($0.width) h=\($0.height)" }
    case .cgRect:
        name = "CGRect"
        contents = axValue.cgRect().map {
            "x=\($0.origin.x) y=\($0.origin.y) w=\($0.width) h=\($0.height)"
        }
    case .cfRange:
        name = "CFRange"
        contents = axValue.cfRange().map { "pos=\($0.location) len=\($0.length)" }
    case .axError:
        name = "AXError"
        contents = axValue.axError().map(\.stringValue)
    case .illegal:
        return "Illegal AXValue"
    @unknown default:
        return "AXValue (\(stringFromAXValueType(type)))"
    }

    guard let contents else { return "AXValue (\(stringFromAXValueType(type)))" }
    return option == .raw ? contents : "<\(name): \(contents)>"
}
