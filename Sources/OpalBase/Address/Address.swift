// Address.swift

import Foundation

public struct Address {
    public static let prefix: String = "bitcoincash"
    public static let separator: String = ":"
    public let string: String
    public let lockingScript: Script
    
    public init(_ string: String) throws {
        let encodedPayload: String
        
        let prefix: String
        
        if string.contains(Address.separator) {
            let splitComponents = string.split(separator: Address.separator)
            guard splitComponents.count == 2 else { throw Error.invalidCashAddressFormat }
            let providedPrefix = String(splitComponents[0])
            guard providedPrefix.caseInsensitiveCompare(Address.prefix) == .orderedSame else { throw Error.invalidCashAddressFormat }
            
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
        let payload = Address.convertFiveBitValuesToData(fiveBitValues: Array(payload5BitValues))
        guard !payload.isEmpty else { throw Error.invalidPayloadLength }
        let versionByte = payload[0]
        let hashData = payload[1...]
        
        switch versionByte {
        case 0x00: // P2PKH
            guard hashData.count == 20 else { throw Error.invalidPayloadLength }
            let hash = PublicKey.Hash(hashData)
            let script = Script.p2pkh_OPCHECKSIG(hash: hash)
            self.lockingScript = script
            
        case 0x08: // P2SH
            guard hashData.count == 20 else { throw Error.invalidPayloadLength }
            let scriptHash = Data(hashData)
            let script = Script.p2sh(scriptHash: scriptHash)
            self.lockingScript = script
            
        default:
            throw Error.unsupportedVersionByte(versionByte)
        }
        
        self.string = encodedPayload
    }
    
    public init(script: Script) throws {
        self.lockingScript = script
        
        switch script {
        case .p2pkh_OPCHECKSIG(let hash), .p2pkh_OPCHECKDATASIG(hash: let hash):
            let versionByte = Data([0x00])
            let payload = versionByte + hash.data
            let payload5BitValues = Address.convertPayloadToFiveBitValues(payload: payload)
            let checksum = try Address.generateChecksum(prefix: Address.prefix, payload5BitValues: payload5BitValues)
            let combined = payload5BitValues + checksum
            self.string = Base32.encode(Data(combined), interpretedAs5Bit: true)
            
        case .p2sh(let scriptHash):
            guard scriptHash.count == 20 else { throw Address.Legacy.Error.invalidScriptType }
            let versionByte = Data([0x08])
            let payload = versionByte + scriptHash
            let payload5BitValues = Address.convertPayloadToFiveBitValues(payload: payload)
            let checksum = try Address.generateChecksum(prefix: Address.prefix, payload5BitValues: payload5BitValues)
            let combined = payload5BitValues + checksum
            self.string = Base32.encode(Data(combined), interpretedAs5Bit: true)
            
        default:
            throw Address.Legacy.Error.invalidScriptType
        }
    }
}

extension Address {
    private static func convertPrefixToFiveBitValues(prefix: String) throws -> [UInt8] {
        var values = [UInt8]()
        for character in prefix {
            guard let asciiValue = character.asciiValue else { throw Error.invalidCharacter(character) }
            let lower5Bits = asciiValue & 0b11111
            values.append(lower5Bits)
        }
        return values
    }
    
    private static func convertPayloadToFiveBitValues(payload: Data) -> [UInt8] {
        var values = [UInt8]()
        
        var bitString = payload.convertToBitString()
        while bitString.count % 5 != 0 { bitString.append("0") }
        
        var index = bitString.startIndex
        while index < bitString.endIndex {
            let nextIndex = bitString.index(index, offsetBy: 5, limitedBy: bitString.endIndex) ?? bitString.endIndex
            let chunk = String(bitString[index..<nextIndex])
            
            if let value = UInt8(chunk, radix: 2) {
                values.append(value)
            }
            
            index = nextIndex
        }
        
        return values
    }
    
    static func convertFiveBitValuesToData(fiveBitValues: [UInt8]) -> Data {
        var bitString = ""
        
        for value in fiveBitValues {
            let binaryString = String(value, radix: 2)
            let paddedBinaryString = String(repeating: "0", count: 5 - binaryString.count) + binaryString
            bitString += paddedBinaryString
        }
        
        let usefulBits = (fiveBitValues.count * 5 / 8) * 8
        
        bitString = String(bitString.prefix(usefulBits))
        
        var data = Data()
        var index = bitString.startIndex
        while index < bitString.endIndex {
            let nextIndex = bitString.index(index, offsetBy: 8, limitedBy: bitString.endIndex) ?? bitString.endIndex
            let byteChunk = String(bitString[index..<nextIndex])
            
            if let byte = UInt8(byteChunk, radix: 2) {
                data.append(byte)
            }
            
            index = nextIndex
        }
        
        return data
    }
    
    private static func generateChecksum(prefix: String, payload5BitValues: [UInt8]) throws -> [UInt8] {
        var values = try Address.convertPrefixToFiveBitValues(prefix: prefix) + [0x00]
        values += payload5BitValues
        let templateForChecksum: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]
        values += templateForChecksum
        let polymod = Polymod.compute(values)
        var checksum = [UInt8]()
        
        for index in 0..<8 {
            let shift = UInt64(5 * (7 - index))
            checksum.append(UInt8((polymod >> shift) & 0x1f))
        }
        
        return checksum
    }
}

extension Address {
    public static func filterBase32(from string: String) -> String {
        let prefixWithSeparator = Address.prefix + Address.separator
        
        let cleanedSubstring: Substring
        if let prefixRange = string.range(
            of: prefixWithSeparator,
            options: [.caseInsensitive, .anchored]
        ) {
            cleanedSubstring = string[prefixRange.upperBound...]
        } else {
            cleanedSubstring = string[string.startIndex...]
        }
        
        let filteredString = cleanedSubstring.reduce(into: String()) { partialResult, candidate in
            guard let asciiValue = candidate.asciiValue else { return }
            
            let normalizedAscii: UInt8
            switch asciiValue {
            case 0x41...0x5A:
                normalizedAscii = asciiValue &+ 0x20
            default:
                normalizedAscii = asciiValue
            }
            
            let normalizedScalar = UnicodeScalar(normalizedAscii)
            let normalizedCharacter = Character(normalizedScalar)
            
            guard Base32.characters.contains(normalizedCharacter)
            else { return }
            
            partialResult.append(normalizedCharacter)
        }
        
        return filteredString
    }
}

extension Address {
    public func makeScriptHash() -> Data {
        let scriptData = lockingScript.data
        return SHA256.hash(scriptData).reversedData
    }
}

extension Address {
    enum Error: Swift.Error, Equatable {
        case invalidCharacter(Character)
        case invalidCashAddressFormat
        case invalidChecksum
        case invalidPayloadLength
        case unsupportedVersionByte(UInt8)
    }
}

extension Address: CustomStringConvertible {
    public var description: String {
        return string
    }
    
    public func generateString(withPrefix: Bool = false) -> String {
        withPrefix ? (Address.prefix + Address.separator + string) : string
    }
}

extension Address: Hashable {
    public static func == (lhs: Address, rhs: Address) -> Bool {
        lhs.lockingScript == rhs.lockingScript
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.lockingScript)
    }
}

extension Address: Sendable {}
extension Address: Equatable {}
