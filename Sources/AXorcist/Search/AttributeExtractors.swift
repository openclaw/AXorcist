// AttributeExtractors.swift - Low-level attribute extraction logic

import ApplicationServices
import Foundation

// MARK: - Internal Fetch Logic Helpers

@MainActor
func determineAttributesToFetch(
    requestedAttributes: [String]?,
    forMultiDefault: Bool,
    targetRole: String?,
    element: Element) -> [String]
{
    if forMultiDefault {
        return defaultMultiAttributes(for: targetRole)
    }

    if let requested = requestedAttributes, !requested.isEmpty {
        return requested
    }

    return fetchAllAttributeNames(from: element)
}

@MainActor
private func fetchAllAttributeNames(from element: Element) -> [String] {
    guard let names = element.attributeNames(), !names.isEmpty else {
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "determineAttributesToFetch: Falling back to defaults; unable to fetch attribute names."))
        return []
    }

    GlobalAXLogger.shared.log(AXLogEntry(
        level: .debug,
        message: "determineAttributesToFetch: No specific attributes requested, fetched all \(names.count)"))
    return names
}

private func defaultMultiAttributes(for role: String?) -> [String] {
    AttributeDefaultSet(role: role).attributes
}

private struct AttributeDefaultSet {
    let role: String?

    var attributes: [String] {
        let base = [
            AXAttributeNames.kAXRoleAttribute,
            AXAttributeNames.kAXValueAttribute,
            AXAttributeNames.kAXTitleAttribute,
            AXAttributeNames.kAXIdentifierAttribute,
        ]
        guard self.role == AXRoleNames.kAXStaticTextRole else { return base }
        return [
            AXAttributeNames.kAXRoleAttribute,
            AXAttributeNames.kAXValueAttribute,
            AXAttributeNames.kAXIdentifierAttribute,
        ]
    }
}

/// Function to get specifically computed attributes for an element
@MainActor
func getComputedAttributes(for element: Element) async -> [String: AttributeData] {
    var computedAttrs: [String: AttributeData] = [:]

    if let name = element.computedName() {
        computedAttrs[AXMiscConstants.computedNameAttributeKey] = AttributeData(
            value: .string(name),
            source: .computed)
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message:
            "getComputedAttributes: Computed name for element " +
                "\(element.briefDescription(option: .raw)) is '\(name)'."))
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message:
            "getComputedAttributes: Element \(element.briefDescription(option: .raw)) " +
                "has no computed name."))
    }

    return computedAttrs
}
