// ECDSA+Error.swift

import Foundation

extension ECDSA {
    enum Error: Swift.Error {
        case invalidCompressedPublicKeyLength
        case invalidCompressedPublicKeyPrefix
    }
}
