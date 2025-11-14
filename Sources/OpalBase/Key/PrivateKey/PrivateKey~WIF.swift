// PrivateKey~WIF.swift

import Foundation

extension PrivateKey {
    var wif: String {
        let versionByte = Data([0x80])
        let compressionByte = Data([0x01])
        let data = versionByte + self.rawData + compressionByte
        let checksum = HASH256.computeChecksum(for: data)
        let wifData = data + checksum
        
        return Base58.encode(wifData)
    }
    
    public init(wif: String) throws {
        guard let decoded = Base58.decode(wif) else { throw Error.cannotDecodeWIF }
        switch decoded.count {
        case 37:
            let versionByte = Data([decoded[0]])
            let rawPrivateKey = decoded[1...32]
            let checksum = decoded[33...36]
            let computedChecksum = HASH256.computeChecksum(for: (versionByte + rawPrivateKey))
            guard checksum == computedChecksum else { throw Error.invalidChecksum }
            self.rawData = rawPrivateKey
        case 38:
            let versionByte = Data([decoded[0]])
            let rawPrivateKey = decoded[1...32]
            let compressionByte = Data([decoded[33]])
            let checksum = decoded[34...37]
            let computedChecksum = HASH256.computeChecksum(for: (versionByte + rawPrivateKey + compressionByte))
            guard checksum == computedChecksum else { throw Error.invalidChecksum }
            self.rawData = rawPrivateKey
        default:
            throw Error.invalidLength
        }
    }
}
