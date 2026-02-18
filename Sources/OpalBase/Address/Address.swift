// Address.swift

import Foundation

public struct Address {
    public static let prefix: String = "bitcoincash"
    public static let separator: String = ":"
    public let string: String
    public let lockingScript: Script
    public let format: Format
    
    public init(_ string: String) throws {
        try self.init(string: string)
    }
    
    public init(string: String) throws {
        if string.contains(Address.separator) {
            self = try Address.parseCashAddress(from: string)
            return
        }
        
        if let cashAddress = try? Address.parseCashAddress(from: string) {
            self = cashAddress
            return
        }
        
        if let legacyAddress = try? Address.parseLegacyAddress(from: string) {
            self = legacyAddress
            return
        }
        
        throw Error.invalidCashAddressFormat
    }
    
    public init(script: Script, format: Format = .standard) throws {
        let string = try Address.makeCashAddressString(for: script, format: format)
        self.init(cashAddressPayload: string, lockingScript: script, format: format)
    }
    
    init(cashAddressPayload: String, lockingScript: Script, format: Format) {
        self.string = cashAddressPayload
        self.lockingScript = lockingScript
        self.format = format
    }
}

extension Address {
    public enum Format: Sendable {
        case standard
        case tokenAware
    }
    
    public var supportsTokens: Bool {
        format == .tokenAware
    }
    
    public var tokenAwareString: String {
        (try? Address.makeCashAddressString(for: lockingScript, format: .tokenAware)) ?? string
    }
    
    static func convertPrefixToFiveBitValues(prefix: String) throws -> [UInt8] {
        var values = [UInt8]()
        for character in prefix {
            guard let asciiValue = character.asciiValue else { throw Error.invalidCharacter(character) }
            let lower5Bits = asciiValue & 0b11111
            values.append(lower5Bits)
        }
        return values
    }
    
    static func convertPayloadToFiveBitValues(payload: Data) throws -> [UInt8] {
        try BitConversion.convertBits([UInt8](payload), from: 8, to: 5, pad: true)
    }
    
    static func convertFiveBitValuesToData(fiveBitValues: [UInt8]) throws -> Data {
        let bytes = try BitConversion.convertBits(fiveBitValues, from: 5, to: 8, pad: false)
        return Data(bytes)
    }
    
    static func generateChecksum(prefix: String, payload5BitValues: [UInt8]) throws -> [UInt8] {
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
    
    private static func makeCashAddressString(for script: Script, format: Format) throws -> String {
        let versionByte = try makeVersionByte(for: script, format: format)
        let payload: Data
        switch script {
        case .p2pkh_OPCHECKSIG(let hash), .p2pkh_OPCHECKDATASIG(hash: let hash):
            payload = Data([versionByte]) + hash.data
        case .p2sh(let scriptHash):
            guard scriptHash.count == 20 else { throw Address.Legacy.Error.invalidScriptType }
            payload = Data([versionByte]) + scriptHash
        default:
            throw Address.Legacy.Error.invalidScriptType
        }
        
        let payload5BitValues = try Address.convertPayloadToFiveBitValues(payload: payload)
        let checksum = try Address.generateChecksum(prefix: Address.prefix, payload5BitValues: payload5BitValues)
        let combined = payload5BitValues + checksum
        return Base32.encode(Data(combined), interpretedAs5Bit: true)
    }
    
    private static func makeVersionByte(for script: Script, format: Format) throws -> UInt8 {
        switch script {
        case .p2pkh_OPCHECKSIG, .p2pkh_OPCHECKDATASIG:
            return format == .tokenAware ? 0x10 : 0x00
        case .p2sh:
            return format == .tokenAware ? 0x18 : 0x08
        default:
            throw Address.Legacy.Error.invalidScriptType
        }
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
