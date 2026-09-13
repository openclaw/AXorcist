import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - CFTypeRef Formatting

@MainActor
public func formatCFTypeRef(
    _ cfValue: CFTypeRef?,
    option: ValueFormatOption = .smart) -> String
{
    guard let value = cfValue else { return "<nil>" }
    let typeID = CFGetTypeID(value)

    return formatCFTypeByID(
        value,
        typeID: typeID,
        option: option)
}

@MainActor
private func formatCFTypeByID(
    _ value: CFTypeRef,
    typeID: CFTypeID,
    option: ValueFormatOption) -> String
{
    switch typeID {
    case AXUIElementGetTypeID():
        return formatAXUIElement(
            value,
            option: option)
    case AXValueGetTypeID():
        let axValue = unsafeDowncast(value, to: AXValue.self)
        return formatAXValue(axValue, option: option)
    case CFStringGetTypeID():
        guard let stringValue = value as? String else {
            return "<Invalid CFString>"
        }
        return "\"\(escapeStringForDisplay(stringValue))\""
    case CFAttributedStringGetTypeID():
        guard let attributedString = value as? NSAttributedString else {
            return "<Invalid CFAttributedString>"
        }
        return "\"\(escapeStringForDisplay(attributedString.string))\""
    case CFBooleanGetTypeID():
        let boolValue = unsafeDowncast(value, to: CFBoolean.self)
        return CFBooleanGetValue(boolValue) ? "true" : "false"
    case CFNumberGetTypeID():
        guard let number = value as? NSNumber else {
            return "<Invalid CFNumber>"
        }
        return number.stringValue
    case CFArrayGetTypeID():
        return formatCFArray(value, option: option)
    case CFDictionaryGetTypeID():
        return formatCFDictionary(value, option: option)
    default:
        let typeDescription = CFCopyTypeIDDescription(typeID) as String? ?? "Unknown"
        axDebugLog(
            "formatCFTypeByID: Unhandled CFType: \(typeDescription) for value. Returning description string.",
            file: #file,
            function: #function,
            line: #line)
        return "<Unhandled CFType: \(typeDescription)>"
    }
}

@MainActor
private func formatAXUIElement(
    _ value: CFTypeRef,
    option: ValueFormatOption) -> String
{
    let axElement = unsafeDowncast(value, to: AXUIElement.self)
    let element = Element(axElement)

    return formatElementValueDescription(
        role: element.role() ?? "Unknown",
        title: element.title(),
        option: option)
}

func formatElementValueDescription(role: String, title: String?, option: ValueFormatOption) -> String {
    guard let title, !title.isEmpty else { return option == .raw ? role : "<\(role)>" }
    let escapedTitle = escapeStringForDisplay(title)
    return option == .raw ? "\(role):\"\(escapedTitle)\"" : "<\(role): \"\(escapedTitle)\">"
}

@MainActor
private func formatCFArray(
    _ value: CFTypeRef,
    option: ValueFormatOption) -> String
{
    let cfArray = unsafeDowncast(value, to: CFArray.self)
    let count = CFArrayGetCount(cfArray)

    if option != .raw || count <= 5 {
        var swiftArray: [String] = []
        for index in 0..<count {
            guard let elementPtr = CFArrayGetValueAtIndex(cfArray, index) else {
                swiftArray.append("<nil_in_array>")
                continue
            }
            swiftArray.append(formatCFTypeRef(
                Unmanaged<CFTypeRef>.fromOpaque(elementPtr).takeUnretainedValue(),
                option: .smart))
        }
        return "[\(swiftArray.joined(separator: ", "))]"
    } else {
        return "<Array of size \(count)>"
    }
}

@MainActor
private func formatCFDictionary(
    _ value: CFTypeRef,
    option: ValueFormatOption) -> String
{
    let cfDict = unsafeDowncast(value, to: CFDictionary.self)
    let count = CFDictionaryGetCount(cfDict)

    if option != .raw || count <= 3 {
        var swiftDict: [String: String] = [:]
        if let nsDict = cfDict as? [String: AnyObject] {
            for (key, val) in nsDict {
                swiftDict[key] = formatCFTypeRef(
                    val,
                    option: .smart)
            }
        } else {
            axWarningLog(
                "formatCFDictionary: Failed to bridge CFDictionary to [String: AnyObject]. " +
                    "Iteration might be incomplete.",
                file: #file,
                function: #function,
                line: #line)
        }
        let pairs = swiftDict.map { "\"\(escapeStringForDisplay($0))\": \($1)" }
            .sorted()
            .joined(separator: ", ")
        return "{\(pairs)}"
    } else {
        return "<Dictionary with \(count) entries>"
    }
}

// MARK: - String Escaping Helper

private func escapeStringForDisplay(_ input: String) -> String {
    var escaped = input
    escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\") // Escape backslashes first
    escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"") // Escape double quotes
    escaped = escaped.replacingOccurrences(of: "\n", with: "\\n") // Escape newlines
    escaped = escaped.replacingOccurrences(of: "\t", with: "\\t") // Escape tabs
    escaped = escaped.replacingOccurrences(of: "\r", with: "\\r") // Escape carriage returns
    return escaped
}
