import Foundation

/// String extension from Scanner
extension String {
    subscript(offset: Int) -> Character {
        self[index(startIndex, offsetBy: offset)]
    }

    func truncated(to length: Int, trailing: String = "...") -> String {
        if self.count > length {
            String(self.prefix(length - trailing.count)) + trailing
        } else {
            self
        }
    }
}
