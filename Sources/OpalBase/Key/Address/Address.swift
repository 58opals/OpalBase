import Foundation

struct Address {
    let prefix: String
    let string: String
    let script: Script
    
    init(_ script: Script) throws {
        self.script = script
        
        switch script {
        case .p2pkh(let hash):
            self.prefix = "bitcoincash"
            let versionByte = Data([0x00])
            let payload = versionByte + hash.data
            let payload5BitValues = Address.payloadTo5BitValues(payload: payload)
            let checksum = try Address.generateChecksum(prefix: prefix, payload5BitValues: payload5BitValues)
            let combined = payload5BitValues + checksum
            self.string = prefix + ":" + Base32.encode(Data(combined))
            
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
    static func == (lhs: Address, rhs: Address) -> Bool {
        lhs.string == rhs.string
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.string)
    }
}
