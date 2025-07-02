// PrivateKey+Error.swift

import Foundation

extension PrivateKey {
    public enum Error: Swift.Error {
        case randomBytesGenerationFailed
        case outOfBounds
        case invalidHexFormat
        case cannotDecodeWIF
        case invalidLength
        case invalidChecksum
    }
}
