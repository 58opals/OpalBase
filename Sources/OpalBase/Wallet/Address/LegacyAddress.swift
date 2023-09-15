// Opal Base by 58 Opals

import Foundation

struct LegacyAddress {
    let representation: Script.Representation
    let hash160: Data
    
    init(publicKey: PublicKey, representation: Script.Representation) {
        self.representation = representation
        self.hash160 = publicKey.hash160
    }
    
    init(hash160: Data, representation: Script.Representation) {
        self.representation = representation
        self.hash160 = hash160
    }
    
    init(address: String) {
        let decoded = Base58().decode(address) as Data
        let prefix = decoded[0]
        switch prefix {
        case 0x00: self.representation = .p2pkh
        case 0x05: self.representation = .p2sh
        default: fatalError()
        }
        let hash160 = decoded[1...20]
        self.hash160 = hash160
    }
    
    var data: Data {
        let checksum = generateChecksum(from: representation.prefix + hash160)
        let data = representation.prefix + hash160 + checksum
        return data
    }
    
    private func generateChecksum(from data: Data) -> Data {
        let firstSHA256 = Cryptography.sha256.hash(data: data)
        let secondSHA256 = Cryptography.sha256.hash(data: Data(firstSHA256))
        let firstFourBytes = Array<UInt8>(secondSHA256)[0...3]
        
        return Data(firstFourBytes)
    }
}

extension LegacyAddress: CustomStringConvertible {
    var description: String {
        Base58().encode(self.data)
    }
}
