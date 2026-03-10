// OpalBase+Address+Error.swift

import Foundation

extension _OpalBase.Address {
    enum Error: Swift.Error, Equatable {
        case invalidCharacter(Character)
        case invalidCashAddressFormat
        case invalidChecksum
        case invalidLegacyChecksum
        case invalidPayloadLength
        case invalidLegacyAddressFormat
        case unsupportedLegacyVersionByte(UInt8)
        case unsupportedVersionByte(UInt8)
    }
}
