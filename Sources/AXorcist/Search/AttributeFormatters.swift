// AttributeFormatters.swift - Attribute formatting logic

import ApplicationServices
import CoreGraphics
import Foundation

/// Helper for formatting raw CFTypeRef values for .textContent output
@MainActor
func formatRawCFValueForTextContent(
    _ rawValue: CFTypeRef?,
    valueFormatOption: ValueFormatOption = .smart) -> String
{
    guard let value = rawValue else { return AXMiscConstants.kAXNotAvailableString }
    let typeID = CFGetTypeID(value)
    if typeID == CFStringGetTypeID() {
        let cfString = unsafeDowncast(value, to: CFString.self)
        return cfString as String
    } else if typeID == CFAttributedStringGetTypeID() {
        let attributedString = unsafeDowncast(value, to: NSAttributedString.self)
        return attributedString.string
    } else if typeID == AXValueGetTypeID() {
        let axValue = unsafeDowncast(value, to: AXValue.self)
        return formatAXValue(axValue, option: valueFormatOption)
    } else if typeID == CFNumberGetTypeID() {
        let number = unsafeDowncast(value, to: NSNumber.self)
        return number.stringValue
    } else if typeID == CFBooleanGetTypeID() {
        let boolValue = unsafeDowncast(value, to: CFBoolean.self)
        return CFBooleanGetValue(boolValue) ? "true" : "false"
    } else {
        let typeDesc = CFCopyTypeIDDescription(typeID) as String? ?? "ComplexType"
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message:
            "formatRawCFValueForTextContent: Encountered unhandled CFTypeID \(typeID) - " +
                "\(typeDesc). Returning placeholder."))
        return "<\(typeDesc)>"
    }
}

@MainActor
func extractAndFormatAttribute(
    element: Element,
    attributeName: String,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption) -> AttributeValue?
{
    GlobalAXLogger.shared.log(AXLogEntry(
        level: .debug,
        message: "extractAndFormatAttribute: '\(attributeName)' for element \(element.briefDescription(option: .raw))"))

    // Try to extract using known attribute handlers first
    if let extractedValue = extractKnownAttribute(
        element: element,
        attributeName: attributeName,
        outputFormat: outputFormat)
    {
        return AttributeValue(from: extractedValue)
    }

    // Fallback to raw attribute value
    return extractRawAttribute(
        element: element,
        attributeName: attributeName,
        outputFormat: outputFormat,
        valueFormatOption: valueFormatOption)
}

@MainActor
private func extractKnownAttribute(element: Element, attributeName: String, outputFormat: OutputFormat) -> Any? {
    AttributeFormatterMapping(attributeName: attributeName)
        .extract(from: element, format: outputFormat)
}

@MainActor
private func extractRawAttribute(
    element: Element,
    attributeName: String,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption) -> AttributeValue?
{
    let rawCFValue = element.rawAttributeValue(named: attributeName)

    if outputFormat == .textContent {
        let formatted = formatRawCFValueForTextContent(rawCFValue, valueFormatOption: valueFormatOption)
        return .string(formatted)
    }

    guard let unwrapped = ValueUnwrapper.unwrap(rawCFValue) else {
        // Only log if rawCFValue was not nil initially
        if rawCFValue != nil {
            let cfTypeID = String(describing: CFGetTypeID(rawCFValue!))
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message:
                "extractAndFormatAttribute: '\(attributeName)' was non-nil CFTypeRef " +
                    "but unwrapped to nil. CFTypeID: \(cfTypeID)"))
            return .string("<Raw CFTypeRef: \(cfTypeID)>")
        }
        return nil
    }

    return AttributeValue(from: unwrapped)
}

private struct AttributeFormatterMapping {
    let attributeName: String

    func extract(from element: Element, format: OutputFormat) -> Any? {
        guard let strategy = self.strategy else { return nil }
        return strategy(element, format)
    }

    private var strategy: ((Element, OutputFormat) -> Any?)? {
        switch self.attributeName {
        case AXAttributeNames.kAXPathHintAttribute:
            { element, _ in
                element.attribute(Attribute<String>(AXAttributeNames.kAXPathHintAttribute))
            }
        case AXAttributeNames.kAXRoleAttribute:
            { element, _ in element.role() }
        case AXAttributeNames.kAXSubroleAttribute:
            { element, _ in element.subrole() }
        case AXAttributeNames.kAXTitleAttribute:
            { element, _ in element.title() }
        case AXAttributeNames.kAXDescriptionAttribute:
            { element, _ in element.descriptionText() }
        case AXAttributeNames.kAXEnabledAttribute:
            AttributeFormatterMapping.booleanFormatter { $0.isEnabled() }
        case AXAttributeNames.kAXFocusedAttribute:
            AttributeFormatterMapping.booleanFormatter { $0.isFocused() }
        case AXAttributeNames.kAXHiddenAttribute:
            AttributeFormatterMapping.booleanFormatter { $0.isHidden() }
        case AXMiscConstants.isIgnoredAttributeKey:
            { element, format in
                let value = element.isIgnored()
                return format == .textContent ? (value ? "true" : "false") : value
            }
        case "PID":
            AttributeFormatterMapping.numericFormatter { $0.pid() }
        case AXAttributeNames.kAXElementBusyAttribute:
            AttributeFormatterMapping.booleanFormatter { $0.isElementBusy() }
        default:
            nil
        }
    }

    private static func booleanFormatter(
        _ extractor: @escaping (Element) -> Bool?) -> ((Element, OutputFormat) -> Any?)
    {
        { element, format in
            guard let value = extractor(element) else { return nil }
            return format == .textContent ? value.description : value
        }
    }

    private static func numericFormatter(
        _ extractor: @escaping (Element) -> Int32?) -> ((Element, OutputFormat) -> Any?)
    {
        { element, format in
            guard let value = extractor(element) else { return nil }
            return format == .textContent ? value.description : value
        }
    }
}
