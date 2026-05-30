// String+LeftPadding.swift

import Foundation

extension String {
    func padLeft(to length: Int, with character: Character = "0") -> String {
        guard length > count else { return self }
        let padCount = length - count
        let padding = String(repeating: String(character), count: padCount)
        return padding + self
    }
}
