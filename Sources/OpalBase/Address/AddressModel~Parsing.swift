// AddressModel~ParsingModel.swift

import Foundation
import OpalCrypto

extension AddressModel {
    private static let standardPublicKeyHashVersionByte: UInt8 = 0x00
    private static let standardScriptHashVersionByte: UInt8 = 0x08
    private static let tokenAwarePublicKeyHashVersionByte: UInt8 = 0x10
    private static let tokenAwareScriptHashVersionByte: UInt8 = 0x18
    
    static func parseCashAddress(from string: String) throws -> AddressModel {
        let encodedPayload: String
        let prefix: String
        
        if string.contains(AddressModel.separator) {
            let splitComponents = string.split(separator: AddressModel.separator)
            guard splitComponents.count == 2 else { throw Error.invalidCashAddressFormat }
            let providedPrefix = String(splitComponents[0])
            guard providedPrefix.caseInsensitiveCompare(AddressModel.prefix) == .orderedSame else {
                throw Error.invalidCashAddressFormat
            }
            
            prefix = AddressModel.prefix
            encodedPayload = String(splitComponents[1])
        } else {
            prefix = AddressModel.prefix
            encodedPayload = string
        }
        
        let hasUppercase = encodedPayload.contains { character in
            guard let asciiValue = character.asciiValue else { return false }
            return (0x41...0x5A).contains(asciiValue)
        }
        let hasLowercase = encodedPayload.contains { character in
            guard let asciiValue = character.asciiValue else { return false }
            return (0x61...0x7A).contains(asciiValue)
        }
        guard !(hasUppercase && hasLowercase) else { throw Error.invalidCashAddressFormat }
        
        let decodedData = try Base32EncodingModel.decode(encodedPayload, interpretedAsFiveBitValues: true)
        guard decodedData.count >= 8 else { throw Error.invalidPayloadLength }
        
        let payload5BitValuesWithChecksum = decodedData
        let payload5BitValues = payload5BitValuesWithChecksum.dropLast(8)
        let checksumValues = payload5BitValuesWithChecksum.suffix(8)
        let checksumInput = try AddressModel.convertPrefixToFiveBitValues(prefix: prefix) + [0x00] + Array(payload5BitValues) + Array(checksumValues)
        guard PolynomialModuloChecksumModel.compute(checksumInput) == 0 else { throw Error.invalidChecksum }
        let payload: Data
        do {
            payload = try AddressModel.convertFiveBitValuesToData(fiveBitValues: Array(payload5BitValues))
        } catch {
            throw Error.invalidPayloadLength
        }
        guard !payload.isEmpty else { throw Error.invalidPayloadLength }
        let versionByte = payload[0]
        let hashData = payload[1...]
        
        switch versionByte {
        case standardPublicKeyHashVersionByte, tokenAwarePublicKeyHashVersionByte:
            guard hashData.count == 20 else { throw Error.invalidPayloadLength }
            let hash = PublicKeyModel.HashModel(hashData)
            let script = ScriptModel.p2pkh_OPCHECKSIG(hash: hash)
            let format: FormatModel = versionByte == tokenAwarePublicKeyHashVersionByte ? .tokenAware : .standard
            return AddressModel(cashAddressPayload: encodedPayload, lockingScript: script, format: format)
        case standardScriptHashVersionByte, tokenAwareScriptHashVersionByte:
            guard hashData.count == 20 else { throw Error.invalidPayloadLength }
            let scriptHash = Data(hashData)
            let script = ScriptModel.p2sh(scriptHash: scriptHash)
            let format: FormatModel = versionByte == tokenAwareScriptHashVersionByte ? .tokenAware : .standard
            return AddressModel(cashAddressPayload: encodedPayload, lockingScript: script, format: format)
        default:
            throw Error.unsupportedVersionByte(versionByte)
        }
    }
    
    static func parseLegacyAddress(from string: String) throws -> AddressModel {
        guard let decoded = Base58EncodingModel.decode(string) else { throw Error.invalidLegacyAddressFormat }
        guard decoded.count >= 5 else { throw Error.invalidLegacyAddressFormat }
        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        let expectedChecksum = SecureHash256Model.computeChecksum(for: payload)
        guard checksum == expectedChecksum else { throw Error.invalidLegacyChecksum }
        guard let versionByte = payload.first else { throw Error.invalidLegacyAddressFormat }
        let hashData = payload.dropFirst()
        guard hashData.count == 20 else { throw Error.invalidLegacyAddressFormat }
        let script: ScriptModel
        switch versionByte {
        case 0x00:
            let hash = PublicKeyModel.HashModel(hashData)
            script = ScriptModel.p2pkh_OPCHECKSIG(hash: hash)
        case 0x05:
            script = ScriptModel.p2sh(scriptHash: Data(hashData))
        default:
            throw Error.unsupportedLegacyVersionByte(versionByte)
        }
        return try AddressModel(script: script, format: .standard)
    }
}
