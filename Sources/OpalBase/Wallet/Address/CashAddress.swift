// Opal Base by 58 Opals

import Foundation

struct CashAddress: Address {
    private let legacyAddress: LegacyAddress
    var representation: Script.Representation { legacyAddress.representation }
    
    init(from publicKey: PublicKey, representation: Script.Representation) {
        self.legacyAddress = LegacyAddress(publicKey: publicKey, representation: representation)
    }
    
    init(from legacyAddress: LegacyAddress) {
        self.legacyAddress = legacyAddress
    }
    
    init(from legacyAddress: String) {
        let decodedLegacyAddress = Base58().decode(legacyAddress) as Data
        let prefixOfLegacyAddress = decodedLegacyAddress.first!
        let hash160 = decodedLegacyAddress[1...20]
        
        switch prefixOfLegacyAddress {
        case Data.Element(0x00): // p2pkh
            self.legacyAddress = LegacyAddress(hash160: hash160, representation: .p2pkh)
        case Data.Element(0x05): // p2sh
            self.legacyAddress = LegacyAddress(hash160: hash160, representation: .p2sh)
        default: fatalError()
        }
    }
    
    private var versionBytes: Data { .init([(firstBit << 7) | (typeBits << 3) | sizeBits]) }
    
    private var payload: Data { return versionBytes + legacyAddress.hash160 }
    
    private let prefix = "bitcoincash"
    private let separator = ":"
    
    private var checksum: UInt {
        var input = Data()
        let maskedByte = UInt8(0b00011111)
        
        for byte in Array<UInt8>(prefix.utf8) {
            input += Data([byte & maskedByte])
        }
        
        let singleZeroByte = Data(repeating: 0, count: 1)
        let eightZeroBytes = Data(repeating: 0, count: 8)
        
        input += singleZeroByte
        input += payload.convertTo5Bit(pad: true)
        input += eightZeroBytes
        
        return PolyMod.encode(input)
    }
    
    var addressString: String {
        let base32Payload = Base32().encode(payload)
        let base32Checksum = Base32().encode(Int(checksum))
        
        return prefix + separator + base32Payload + base32Checksum
    }
}

extension CashAddress {
    private var dataSize: Int { legacyAddress.hash160.count }
    
    private var firstBit: UInt8 { 0b0 }
    
    private var typeBits: UInt8 {
        let leadingCharacter = legacyAddress.description.first!
        
        switch leadingCharacter {
        case "1": return 0b0000 // p2pkh
        case "3": return 0b0001 // p2sh
        default: fatalError()
        }
    }
    
    private var sizeBits: UInt8 {
        switch dataSize*8 {
        case 160: return 0b000
        case 192: return 0b001
        case 224: return 0b010
        case 256: return 0b011
        case 320: return 0b100
        case 384: return 0b101
        case 448: return 0b110
        case 512: return 0b111
        default: fatalError()
        }
    }
}

extension CashAddress: CustomStringConvertible {
    var description: String {
        self.addressString
    }
}
