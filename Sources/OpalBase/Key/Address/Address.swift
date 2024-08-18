import Foundation

public struct Address {
    public let prefix: String = "bitcoincash"
    public let string: String
    public let lockingScript: Script
    
    public init(_ string: String) throws {
        let encodedPayload: String
        
        if string.contains(":") {
            let splitComponents = string.split(separator: ":")
            guard splitComponents.count == 2 else { throw Error.invalidCashAddressFormat }
            guard String(splitComponents[0]) == self.prefix else { throw Error.invalidCashAddressFormat }
            encodedPayload = String(splitComponents[1])
        } else {
            encodedPayload = string
        }
        
        let decodedData = try Base32.decode(encodedPayload, interpretedAs5Bit: true)
        
        let payload5BitValuesWithChecksum = decodedData
        let payload5BitValues = payload5BitValuesWithChecksum.dropLast(8)
        let payload = Address.fiveBitValuesToData(fiveBitValues: payload5BitValues.bytes)
        let versionByte = payload[0]
        let hashData = payload[1...]
        
        switch versionByte {
        case 0x00: // P2PKH
            guard hashData.count == 20 else { throw Error.invalidPayloadLength }
            let hash = PublicKey.Hash(hashData)
            let script = Script.p2pkh(hash: hash)
            self.lockingScript = script
            
        default:
            throw Error.unsupportedVersionByte(versionByte)
        }
        
        self.string = string
    }
    
    public init(script: Script) throws {
        self.lockingScript = script
        
        switch script {
        case .p2pkh(let hash):
            let versionByte = Data([0x00])
            let payload = versionByte + hash.data
            let payload5BitValues = Address.payloadTo5BitValues(payload: payload)
            let checksum = try Address.generateChecksum(prefix: prefix, payload5BitValues: payload5BitValues)
            let combined = payload5BitValues + checksum
            self.string = prefix + ":" + Base32.encode(Data(combined), interpretedAs5Bit: true)
            
        default:
            throw Address.Legacy.Error.invalidScriptType
        }
    }
}

extension Address {
    private static func prefixTo5BitValues(prefix: String) throws -> [UInt8] {
        var values = [UInt8]()
        for character in prefix {
            guard let asciiValue = character.asciiValue else { throw Error.invalidCharacter(character) }
            let lower5Bits = asciiValue & 0b11111
            values.append(lower5Bits)
        }
        return values
    }
    
    private static func payloadTo5BitValues(payload: Data) -> [UInt8] {
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
    
    static func fiveBitValuesToData(fiveBitValues: [UInt8]) -> Data {
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
        var values = try Address.prefixTo5BitValues(prefix: prefix) + [0x00]
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

extension Address: Hashable {
    public static func == (lhs: Address, rhs: Address) -> Bool {
        lhs.string == rhs.string
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.string)
    }
}

extension Address: CustomStringConvertible {
    public var description: String {
        return string
    }
}
