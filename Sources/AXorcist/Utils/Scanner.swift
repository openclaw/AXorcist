// Scanner.swift - Custom scanner implementation (Scanner)

import Foundation

/// Internal cursor used to parse accessibility geometry and ranges.
class Scanner {
    // MARK: Lifecycle

    init(string: String) {
        self.string = string
        self.location = string.startIndex
    }

    // MARK: Internal

    let string: String
    private(set) var location: String.Index

    @discardableResult
    func scanCharacters(in charSet: CustomCharacterSet) -> String? {
        let start = self.location
        while self.location < self.string.endIndex, charSet.contains(self.string[self.location]) {
            self.string.formIndex(after: &self.location)
        }
        return start == self.location ? nil : String(self.string[start..<self.location])
    }

    // MARK: - Specific Character and String Scanning

    @discardableResult func scan(character: Character, options: NSString.CompareOptions = []) -> Character? {
        guard self.location < self.string.endIndex else { return nil }
        let characterString = String(character)
        if characterString
            .compare(String(self.string[self.location]), options: options, range: nil, locale: nil) == .orderedSame
        {
            self.string.formIndex(after: &self.location)
            return character
        }
        return nil
    }

    // MARK: - Integer Scanning

    func scanInteger<T: FixedWidthInteger & SignedInteger>() -> T? {
        let savepoint = self.location
        self.scanWhitespaces()
        let start = self.location
        if self.scan(character: "-") == nil {
            self.scan(character: "+")
        }
        guard self.scanCharacters(in: .decimalDigits) != nil,
              let value = T(self.string[start..<self.location], radix: 10)
        else {
            self.location = savepoint
            return nil
        }
        return value
    }

    // MARK: - Floating Point Scanning

    /// Attempt to parse Double with a compact implementation
    func scanDouble() -> Double? {
        self.scanWhitespaces()
        let initialLocation = self.location

        // Parse sign
        if self.scan(character: "-") == nil {
            self.scan(character: "+")
        }
        var hasDigits = false

        // Parse integer part
        if self.scanCharacters(in: .decimalDigits) != nil {
            hasDigits = true
        }

        // Parse fractional part
        let dotLocation = self.location
        if self.scan(character: ".") != nil {
            if self.scanCharacters(in: .decimalDigits) != nil {
                hasDigits = true
            } else {
                // Revert dot scan if not followed by digits
                self.location = dotLocation
            }
        }

        // If no digits found in either integer or fractional part, revert and return nil
        if !hasDigits {
            self.location = initialLocation
            return nil
        }

        // Parse exponent
        let expLocation = self.location
        if self.scan(character: "e", options: .caseInsensitive) != nil {
            if self.scan(character: "-") == nil {
                self.scan(character: "+")
            }
            if self.scanCharacters(in: .decimalDigits) == nil {
                // Revert exponent scan if not followed by valid digits
                self.location = expLocation
            }
        }

        // Convert the complete token once; separate exponent scaling can underflow or produce NaN for zero.
        if let value = Double(self.string[initialLocation..<self.location]) {
            return value
        }

        // If conversion fails, revert everything
        self.location = initialLocation
        return nil
    }

    // MARK: - Whitespace Scanning

    func scanWhitespaces() {
        _ = self.scanCharacters(in: .whitespacesAndNewlines)
    }
}
