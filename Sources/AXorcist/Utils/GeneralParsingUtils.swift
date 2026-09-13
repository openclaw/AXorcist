import Foundation

/// Parses a JSON array or a comma-separated list, optionally enclosed in brackets.
/// JSON preserves explicit empty strings; comma-separated input drops empty components.
@MainActor
public func decodeExpectedArray(fromString: String) -> [String]? {
    let trimmed = fromString.trimmingCharacters(in: .whitespacesAndNewlines)
    let bracketed = trimmed.hasPrefix("[") && trimmed.hasSuffix("]")

    if bracketed {
        do {
            let decoded = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
            if let strings = decoded as? [String] {
                return strings
            }
            if let values = decoded as? [Any] {
                return values.map { ($0 as? String) ?? String(describing: $0) }
            }
        } catch {
            axDebugLog("JSON decoding failed for string: \(trimmed). Error: \(error.localizedDescription)")
        }
    }

    let contents = bracketed ? String(trimmed.dropFirst().dropLast()) : trimmed
    guard !contents.isEmpty else { return bracketed ? [] : nil }
    return contents.components(separatedBy: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}
