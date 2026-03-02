// PublicKeyModel+ExtendedModel.swift

import Foundation
import OpalCrypto

extension PublicKeyModel {
    struct ExtendedModel {
        let publicKey: Data
        let chainCode: Data
        let depth: UInt8
        let parentFingerprint: Data
        let childIndexNumber: UInt32
        
        init(publicKey: Data, chainCode: Data, depth: UInt8, parentFingerprint: Data, childIndexNumber: UInt32) {
            self.publicKey = publicKey
            self.chainCode = chainCode
            self.depth = depth
            self.parentFingerprint = parentFingerprint
            self.childIndexNumber = childIndexNumber
        }
        
        init(xpub: String) throws {
            guard let data = Base58EncodingModel.decode(xpub) else { throw Error.invalidFormat }
            guard data.count == 82 else { throw Error.invalidLength }
            
            let payload = data.prefix(data.count - 4)
            let checksum = data.suffix(4)
            let computedChecksum = SecureHash256Model.computeChecksum(for: payload)
            guard checksum.elementsEqual(computedChecksum) else { throw Error.invalidChecksum }
            
            let version = UInt32(bigEndian: payload[0..<4].withUnsafeBytes { $0.load(as: UInt32.self) })
            guard version == 0x0488b21e else { throw Error.invalidVersion }
            
            self.depth = payload[4]
            self.parentFingerprint = Data(payload[5..<9])
            self.childIndexNumber = UInt32(bigEndian: payload[9..<13].withUnsafeBytes { $0.load(as: UInt32.self) })
            self.chainCode = Data(payload[13..<45])
            self.publicKey = Data(payload[45..<78])
        }
        
        init(extendedPrivateKey: PrivateKeyModel.ExtendedModel) throws {
            self.publicKey = try PublicKeyModel(privateKey: .init(data: extendedPrivateKey.privateKey)).compressedData
            self.chainCode = extendedPrivateKey.chainCode
            self.depth = extendedPrivateKey.depth
            self.parentFingerprint = extendedPrivateKey.parentFingerprint
            self.childIndexNumber = extendedPrivateKey.childIndexNumber
        }
    }
}

extension PublicKeyModel.ExtendedModel: Hashable {
    static func == (lhs: PublicKeyModel.ExtendedModel, rhs: PublicKeyModel.ExtendedModel) -> Bool {
        lhs.publicKey == rhs.publicKey &&
        lhs.chainCode == rhs.chainCode &&
        lhs.depth == rhs.depth &&
        lhs.parentFingerprint == rhs.parentFingerprint &&
        lhs.childIndexNumber == rhs.childIndexNumber
    }
}

extension PublicKeyModel.ExtendedModel: CustomDebugStringConvertible {
    var debugDescription: String {
        """
        ExtendedPublicKey(
            publicKey: \(publicKey.hexadecimalString),
            chainCode: \(chainCode.hexadecimalString),
            depth: \(depth),
            parentFingerprint: \(parentFingerprint.hexadecimalString),
            childIndexNumber: \(childIndexNumber)
        )
        """
    }
}

extension PublicKeyModel.ExtendedModel {
    private func deriveChildPublicKey(at index: UInt32) throws -> PublicKeyModel.ExtendedModel {
        let isHardened = HardenModel.checkHardened(index)
        guard !isHardened else { throw PublicKeyModel.Error.hardenedDerivation }
        
        var data = Data()
        
        data.append(publicKey)
        data.append(index.bigEndianData)
        
        let hmac = HashBasedMessageAuthenticationCodeSecureHashAlgorithm512Model.hash(data, key: chainCode)
        let leftHMACPart = Data(hmac.prefix(32))
        let rightHMACPart = Data(hmac.suffix(32))
        
        let childPublicKey: Data
        do {
            childPublicKey = try StandardsForEfficientCryptography256k1CurveModel.OperationModel.tweakAddPublicKey(publicKey,
                                                                       tweakData32Bytes: leftHMACPart,
                                                                       format: .compressed)
        } catch {
            throw PublicKeyModel.Error.publicKeyDerivationFailed
        }
        let childChainCode = rightHMACPart
        let childDepth = depth + 1
        let childParentFingerprint = Data(SecureHash160Model.hash(publicKey).prefix(4))
        let childIndexNumber = index
        
        return .init(publicKey: childPublicKey, chainCode: childChainCode, depth: childDepth, parentFingerprint: childParentFingerprint, childIndexNumber: childIndexNumber)
    }
    
    func deriveChild(at path: DerivationPathModel) throws -> PublicKeyModel.ExtendedModel {
        try deriveChild(at: path.makeIndices())
    }
    
    func deriveChild(at indices: [UInt32]) throws -> PublicKeyModel.ExtendedModel {
        var extendedKey = self
        let startingDepth = Int(self.depth)
        
        guard indices.count >= startingDepth else {
            throw PublicKeyModel.Error.derivationPathTooShort
        }
        
        for index in indices.dropFirst(startingDepth) {
            guard !HardenModel.checkHardened(index) else { throw PublicKeyModel.Error.hardenedDerivation }
            extendedKey = try extendedKey.deriveChildPublicKey(at: index)
        }
        
        return extendedKey
    }
}

extension PublicKeyModel.ExtendedModel {
    var address: String {
        Base58EncodingModel.encode(serialize())
    }
    
    func serialize() -> Data {
        var data = Data()
        let version = UInt32(0x0488b21e.littleEndian) // xpub
        data.append(version.bigEndianData)
        data.append(Data([depth]))
        data.append(parentFingerprint)
        data.append(childIndexNumber.bigEndianData)
        data.append(chainCode)
        data.append(publicKey)
        let checksum = SecureHash256Model.hash(data).prefix(4)
        data.append(checksum)
        return data
    }
}

extension PublicKeyModel.ExtendedModel: Sendable {}
extension PublicKeyModel.ExtendedModel: Equatable {}
