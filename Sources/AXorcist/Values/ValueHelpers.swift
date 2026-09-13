import ApplicationServices
import CoreGraphics // For CGPoint, CGSize etc.
import Foundation

// debug() is assumed to be globally available from Logging.swift
// Accessibility constants are now available through namespaced enums like AXAttributeNames, AXRoleNames, etc.

// ValueUnwrapper has been moved to its own file: ValueUnwrapper.swift

// MARK: - Attribute Value Accessors

@MainActor
public func copyAttributeValue(element: AXUIElement, attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

    // Use new error extension for cleaner error checking
    if error != .success {
        if error != .noValue, error != .attributeUnsupported {
            axDebugLog("Error copying attribute '\(attribute)': \(error.rawValue)")
        }
        return nil
    }
    return value
}

@MainActor
public func axValue<T>(
    of element: AXUIElement,
    attr: String) -> T?
{
    let rawCFValue = copyAttributeValue(element: element, attribute: attr)
    // ValueUnwrapper.unwrap and castValueToType are assumed to be refactored
    // to use GlobalAXLogger internally or handle their own logging if necessary.
    let unwrappedValue = ValueUnwrapper.unwrap(rawCFValue)

    guard let value = unwrappedValue else {
        // Minimal log here, ValueUnwrapper might provide more detail if needed.
        axDebugLog(
            "axValue: ValueUnwrapper returned nil for attribute '\(attr)'.",
            file: #file,
            function: #function,
            line: #line)
        return nil
    }

    // castValueToType will use GlobalAXLogger or handle its own logging.
    return castValueToType(value, expectedType: T.self, attr: attr)
}

// MARK: - AXValueType String Helper

public func stringFromAXValueType(_ type: AXValueType) -> String {
    switch type {
    case .cgPoint: "CGPoint (kAXValueCGPointType)"
    case .cgSize: "CGSize (kAXValueCGSizeType)"
    case .cgRect: "CGRect (kAXValueCGRectType)"
    case .cfRange: "CFRange (kAXValueCFRangeType)"
    case .axError: "AXError (kAXValueAXErrorType)"
    case .illegal: "Illegal (kAXValueIllegalType)"
    default:
        "Unknown AXValueType (rawValue: \(type.rawValue))"
    }
}
