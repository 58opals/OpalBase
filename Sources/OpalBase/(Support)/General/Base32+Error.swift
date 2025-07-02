// Base32+Error.swift

import Foundation

extension Base32 {
    enum Error: Swift.Error {
        case invalidCharacterFound
    }
}
