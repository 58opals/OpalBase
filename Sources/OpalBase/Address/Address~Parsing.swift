// Address~Parsing.swift

import Foundation

extension Address {
    private static let standardPublicKeyHashVersionByte: UInt8 = 0x00
    private static let standardScriptHashVersionByte: UInt8 = 0x08
    private static let tokenAwarePublicKeyHashVersionByte: UInt8 = 0x10
    private static let tokenAwareScriptHashVersionByte: UInt8 = 0x18
    
    static func parseCashAddress(from string: String) throws -> Address {
        let encodedPayload: String
        let prefix: String
        
        if string.contains(Address.separator) {
            let splitComponents = string.split(separator: Address.separator)
            guard splitComponents.count == 2 else { throw Error.invalidCashAddressFormat }
            let providedPrefix = String(splitComponents[0])
            guard providedPrefix.caseInsensitiveCompare(Address.prefix) == .orderedSame else {
                throw Error.invalidCashAddressFormat
            }
            
            prefix = Address.prefix
            encodedPayload = String(splitComponents[1])
        } else {
            prefix = Address.prefix
            encodedPayload = string
        }
        
        let decodedData = try Base32.decode(encodedPayload, interpretedAs5Bit: true)
        guard decodedData.count >= 8 else { throw Error.invalidPayloadLength }
        
        let payload5BitValuesWithChecksum = decodedData
        let payload5BitValues = payload5BitValuesWithChecksum.dropLast(8)
        let checksumValues = payload5BitValuesWithChecksum.suffix(8)
        let checksumInput = try Address.convertPrefixToFiveBitValues(prefix: prefix) + [0x00] + Array(payload5BitValues) + Array(checksumValues)
        guard Polymod.compute(checksumInput) == 0 else { throw Error.invalidChecksum }
        let payload: Data
        do {
            payload = try Address.convertFiveBitValuesToData(fiveBitValues: Array(payload5BitValues))
        } catch {
            throw Error.invalidPayloadLength
        }
        guard !payload.isEmpty else { throw Error.invalidPayloadLength }
        let versionByte = payload[0]
        let hashData = payload[1...]
        
        switch versionByte {
        case standardPublicKeyHashVersionByte, tokenAwarePublicKeyHashVersionByte:
            guard hashData.count == 20 else { throw Error.invalidPayloadLength }
            let hash = PublicKey.Hash(hashData)
            let script = Script.p2pkh_OPCHECKSIG(hash: hash)
            let format: Format = versionByte == tokenAwarePublicKeyHashVersionByte ? .tokenAware : .standard
            return Address(cashAddressPayload: encodedPayload, lockingScript: script, format: format)
        case standardScriptHashVersionByte, tokenAwareScriptHashVersionByte:
            guard hashData.count == 20 else { throw Error.invalidPayloadLength }
            let scriptHash = Data(hashData)
            let script = Script.p2sh(scriptHash: scriptHash)
            let format: Format = versionByte == tokenAwareScriptHashVersionByte ? .tokenAware : .standard
            return Address(cashAddressPayload: encodedPayload, lockingScript: script, format: format)
        default:
            throw Error.unsupportedVersionByte(versionByte)
        }
    }
    
    static func parseLegacyAddress(from string: String) throws -> Address {
        guard let decoded = Base58.decode(string) else { throw Error.invalidLegacyAddressFormat }
        guard decoded.count >= 5 else { throw Error.invalidLegacyAddressFormat }
        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        let expectedChecksum = HASH256.computeChecksum(for: payload)
        guard checksum == expectedChecksum else { throw Error.invalidLegacyChecksum }
        guard let versionByte = payload.first else { throw Error.invalidLegacyAddressFormat }
        let hashData = payload.dropFirst()
        guard hashData.count == 20 else { throw Error.invalidLegacyAddressFormat }
        let script: Script
        switch versionByte {
        case 0x00:
            let hash = PublicKey.Hash(hashData)
            script = Script.p2pkh_OPCHECKSIG(hash: hash)
        case 0x05:
            script = Script.p2sh(scriptHash: Data(hashData))
        default:
            throw Error.unsupportedLegacyVersionByte(versionByte)
        }
        return try Address(script: script, format: .standard)
    }
}
