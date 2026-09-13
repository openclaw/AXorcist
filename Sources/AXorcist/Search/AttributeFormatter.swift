// AttributeFormatter.swift - Contains functions for formatting element attributes for display

import ApplicationServices
import Foundation

/// Helper function to format the parent attribute
@MainActor
func formatParentAttribute(
    _ parent: Element?,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption) -> AttributeValue
{
    guard let parentElement = parent else { return .null }
    if outputFormat == .textContent {
        return .string("Element: \(parentElement.role() ?? "?Role")")
    } else {
        return .string(parentElement.briefDescription(option: valueFormatOption))
    }
}

/// Helper function to format the children attribute
@MainActor
func formatChildrenAttribute(
    _ children: [Element]?,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption) -> AttributeValue
{
    guard let actualChildren = children, !actualChildren.isEmpty else {
        return .null
    }

    let descriptions = actualChildren.map { $0.briefDescription(option: valueFormatOption) }
    return outputFormat == .textContent
        ? .string("[\(descriptions.joined(separator: ", "))]")
        : .array(descriptions.map { .string($0) })
}

/// Helper function to format the focused UI element attribute
@MainActor
func formatFocusedUIElementAttribute(
    _ focusedElement: Element?,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption) -> AttributeValue
{
    guard let actualFocusedElement = focusedElement else { return .null }
    if outputFormat == .textContent {
        return .string(
            "Focused: \(actualFocusedElement.role() ?? "?Role") - \(actualFocusedElement.title() ?? "?Title")")
    } else {
        return .string(actualFocusedElement.briefDescription(option: valueFormatOption))
    }
}
