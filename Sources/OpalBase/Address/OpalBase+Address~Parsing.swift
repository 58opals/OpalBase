// OpalBase+Address~Parsing.swift

import Foundation

extension _OpalBase.Address {
    private static let standardPublicKeyHashVersionByte: UInt8 = 0x00
    private static let standardScriptHashVersionByte: UInt8 = 0x08
    private static let tokenAwarePublicKeyHashVersionByte: UInt8 = 0x10
    private static let tokenAwareScriptHashVersionByte: UInt8 = 0x18
    
    static func parseCashAddr(
        from string: String,
        network: OpalBase.Network.Environment
    ) throws -> OpalBase.Address {
        let encodedPayload: String
        let prefix: String
        let caseCheckString: String
        let expectedPrefix = OpalBase.Address.cashAddrPrefix(for: network)
        
        if string.contains(OpalBase.Address.separator) {
            let splitComponents = string.split(
                separator: Character(OpalBase.Address.separator),
                omittingEmptySubsequences: false
            )
            guard splitComponents.count == 2 else { throw Error.invalidCashAddrFormat }
            let providedPrefix = String(splitComponents[0])
            guard providedPrefix.caseInsensitiveCompare(expectedPrefix) == .orderedSame else {
                throw Error.invalidCashAddrFormat
            }
            
            prefix = expectedPrefix
            encodedPayload = String(splitComponents[1])
            caseCheckString = providedPrefix + encodedPayload
        } else {
            prefix = expectedPrefix
            encodedPayload = string
            caseCheckString = encodedPayload
        }
        
        let hasUppercase = caseCheckString.contains { character in
            guard let asciiValue = character.asciiValue else { return false }
            return (0x41...0x5A).contains(asciiValue)
        }
        let hasLowercase = caseCheckString.contains { character in
            guard let asciiValue = character.asciiValue else { return false }
            return (0x61...0x7A).contains(asciiValue)
        }
        guard !(hasUppercase && hasLowercase) else { throw Error.invalidCashAddrFormat }
        
        let canonicalPayload = encodedPayload.lowercased()
        let decodedData = try OpalCryptoAdapter.decodeBase32(
            encodedPayload,
            interpretedAsFiveBitValues: true
        )
        guard decodedData.count >= 8 else { throw Error.invalidPayloadLength }
        
        let payload5BitValuesWithChecksum = decodedData
        let payload5BitValues = payload5BitValuesWithChecksum.dropLast(8)
        let checksumValues = payload5BitValuesWithChecksum.suffix(8)
        let checksumInput = try OpalBase.Address.convertPrefixToFiveBitValues(prefix: prefix) + [0x00] + Array(payload5BitValues) + Array(checksumValues)
        guard OpalCryptoAdapter.computePolymod(checksumInput) == 0 else { throw Error.invalidChecksum }
        let payload: Data
        do {
            payload = try OpalBase.Address.convertFiveBitValuesToData(fiveBitValues: Array(payload5BitValues))
        } catch {
            throw Error.invalidPayloadLength
        }
        guard !payload.isEmpty else { throw Error.invalidPayloadLength }
        let versionByte = payload[0]
        let hashData = payload[1...]
        
        switch versionByte {
        case standardPublicKeyHashVersionByte, tokenAwarePublicKeyHashVersionByte:
            guard hashData.count == 20 else { throw Error.invalidPayloadLength }
            let hash = OpalBase.Key.PublicKey.Hash(hashData)
            let script = OpalBase.Script.p2pkh_OPCHECKSIG(hash: hash)
            let format: Format = versionByte == tokenAwarePublicKeyHashVersionByte ? .tokenAware : .standard
            return OpalBase.Address(
                cashAddrPayload: canonicalPayload,
                lockingScript: script,
                format: format,
                network: network
            )
        case standardScriptHashVersionByte, tokenAwareScriptHashVersionByte:
            guard hashData.count == 20 else { throw Error.invalidPayloadLength }
            let scriptHash = Data(hashData)
            let script = OpalBase.Script.p2sh(scriptHash: scriptHash)
            let format: Format = versionByte == tokenAwareScriptHashVersionByte ? .tokenAware : .standard
            return OpalBase.Address(
                cashAddrPayload: canonicalPayload,
                lockingScript: script,
                format: format,
                network: network
            )
        default:
            throw Error.unsupportedVersionByte(versionByte)
        }
    }
    
    static func parseLegacyAddress(from string: String) throws -> OpalBase.Address {
        guard let decoded = OpalCryptoAdapter.decodeBase58(string) else { throw Error.invalidLegacyAddressFormat }
        guard decoded.count >= 5 else { throw Error.invalidLegacyAddressFormat }
        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        let expectedChecksum = Data(OpalCryptoAdapter.hash256(Data(payload)).prefix(4))
        guard checksum == expectedChecksum else { throw Error.invalidLegacyChecksum }
        guard let versionByte = payload.first else { throw Error.invalidLegacyAddressFormat }
        let hashData = payload.dropFirst()
        guard hashData.count == 20 else { throw Error.invalidLegacyAddressFormat }
        let script: OpalBase.Script
        switch versionByte {
        case 0x00:
            let hash = OpalBase.Key.PublicKey.Hash(hashData)
            script = OpalBase.Script.p2pkh_OPCHECKSIG(hash: hash)
        case 0x05:
            script = OpalBase.Script.p2sh(scriptHash: Data(hashData))
        default:
            throw Error.unsupportedLegacyVersionByte(versionByte)
        }
        return try OpalBase.Address(script: script, format: .standard)
    }
}
