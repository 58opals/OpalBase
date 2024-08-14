import Foundation

extension PrivateKey {
    enum Error: Swift.Error {
        case randomBytesGenerationFailed
        case outOfBounds
        case invalidHexFormat
        case cannotDecodeWIF
        case invalidLength
        case invalidChecksum
    }
}
