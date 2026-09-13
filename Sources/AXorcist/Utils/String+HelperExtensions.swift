import Foundation

extension String {
    func truncated(to length: Int, trailing: String = "...") -> String {
        if self.count > length {
            String(self.prefix(length - trailing.count)) + trailing
        } else {
            self
        }
    }
}
