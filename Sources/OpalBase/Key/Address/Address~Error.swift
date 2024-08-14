import Foundation

extension Address {
    enum Error: Swift.Error {
        case invalidCharacter(Character)
        case invalidCashAddressFormat
        case invalidChecksum
        case invalidPayloadLength
        case unsupportedVersionByte(UInt8)
    }
}

extension Address.Error: Equatable {}
