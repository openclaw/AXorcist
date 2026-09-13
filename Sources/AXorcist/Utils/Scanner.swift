// Scanner.swift - Custom scanner implementation (Scanner)

import Foundation

/// Internal cursor used to parse accessibility geometry and ranges.
class Scanner {
    // MARK: Lifecycle

    init(string: String) {
        self.string = string
    }

    // MARK: Internal

    let string: String
    var location = 0

    /// Scans characters that ARE in the provided set (like original Scanner's scanUpTo/scan(characterSet:))
    @discardableResult func scanCharacters(in charSet: CustomCharacterSet) -> String? {
        let initialLocation = self.location
        var characters = String()

        while self.location < self.string.count, charSet.contains(self.string[self.location]) {
            characters.append(self.string[self.location])
            self.location += 1
        }

        if characters.isEmpty {
            self.location = initialLocation // Revert if nothing was scanned
            return nil
        }
        return characters
    }

    // MARK: - Specific Character and String Scanning

    @discardableResult func scan(character: Character, options: NSString.CompareOptions = []) -> Character? {
        guard self.location < self.string.count else { return nil }
        let characterString = String(character)
        if characterString
            .compare(String(self.string[self.location]), options: options, range: nil, locale: nil) == .orderedSame
        {
            self.location += 1
            return character
        }
        return nil
    }

    @discardableResult func scan(string: String, options: NSString.CompareOptions = []) -> String? {
        let savepoint = self.location
        var characters = String()

        for character in string {
            if let charScanned = self.scan(character: character, options: options) {
                characters.append(charScanned)
            } else {
                self.location = savepoint // Revert on failure
                return nil
            }
        }

        // If we scanned the whole string, it's a match.
        return characters
    }

    // MARK: - Integer Scanning

    func scanSign() -> Int? {
        self.scan(dictionary: ["+": 1, "-": -1])
    }

    func scanInteger<T: SignedInteger>() -> T? {
        let savepoint = self.location
        self.scanWhitespaces()

        // Parse sign if present
        let sign = self.scanSign() ?? 1

        // Parse digits
        guard let digitString = self.scanDigits() else {
            // If we found a sign but no digits, revert and return nil
            if sign != 1 {
                self.location = savepoint
            }
            return nil
        }

        // Calculate final value with sign applied
        return T(sign) * self.integerValue(from: digitString)
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

    // MARK: - Dictionary-based Scanning

    func scan<T>(dictionary: [String: T], options: NSString.CompareOptions = []) -> T? {
        for (key, value) in dictionary where self.scan(string: key, options: options) != nil {
            // Original Scanner asserts string == key, which is true if scan(string:) returns non-nil.
            return value
        }
        return nil
    }

    // MARK: Private

    /// Private helper that scans and returns a string of digits
    private func scanDigits() -> String? {
        self.scanCharacters(in: .decimalDigits)
    }

    /// Calculate integer value from digit string with given base
    private func integerValue<T: BinaryInteger>(from digitString: String, base: T = 10) -> T {
        digitString.reduce(T(0)) { result, char in
            result * base + T(Int(String(char))!)
        }
    }
}
