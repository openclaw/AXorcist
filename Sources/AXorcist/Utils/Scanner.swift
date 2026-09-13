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
        let sign: Double = (scan(character: "-") != nil) ? -1.0 : { _ = self.scan(character: "+"); return 1.0 }()

        // Buffer to build the numeric string
        var numberStr = ""
        var hasDigits = false

        // Parse integer part
        if let digits = scanCharacters(in: .decimalDigits) {
            numberStr += digits
            hasDigits = true
        }

        // Parse fractional part
        let dotLocation = self.location
        if self.scan(character: ".") != nil {
            if let fractionDigits = scanCharacters(in: .decimalDigits) {
                numberStr += "."
                numberStr += fractionDigits
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
        var exponent = 0
        let expLocation = self.location
        if self.scan(character: "e", options: .caseInsensitive) != nil {
            let expSign: Double = (scan(character: "-") != nil) ? -1.0 : { _ = self.scan(character: "+"); return 1.0 }()

            if let expDigits = scanCharacters(in: .decimalDigits), let expValue = Int(expDigits) {
                exponent = Int(expSign) * expValue
            } else {
                // Revert exponent scan if not followed by valid digits
                self.location = expLocation
            }
        }

        // Convert to final double value
        if var value = Double(numberStr) {
            value *= sign
            if exponent != 0 {
                value *= pow(10.0, Double(exponent))
            }
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
