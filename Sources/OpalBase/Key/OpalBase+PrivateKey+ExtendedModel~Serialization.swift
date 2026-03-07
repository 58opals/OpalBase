// OpalBase.PrivateKey+ExtendedModel~Serialization.swift

import Foundation

extension _OpalBase.PrivateKey.ExtendedModel {
    var address: String {
        return Base58Model.encode(serialize())
    }

    func serialize() -> Data {
        var data = Data()
        let version = UInt32(0x0488ade4.littleEndian) // xprv
        data.append(version.bigEndianData)
        data.append(Data([self.depth]))
        data.append(self.parentFingerprint)
        data.append(self.childIndexNumber.bigEndianData)
        data.append(self.chainCode)
        data.append(Data([0x00]) + self.privateKey)
        let checksum = HASH256Model.hash(data).prefix(4)
        data.append(checksum)

        return data
    }
}
