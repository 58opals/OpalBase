import Foundation
import BigInt

extension PrivateKey {
    struct Extended {
        let privateKey: Data
        let chainCode: Data
        let depth: UInt8
        let parentFingerprint: Data
        let childNumber: UInt32
        
        init(rootKey: PrivateKey.Extended.Root) {
            self.privateKey = rootKey.privateKey
            self.chainCode = rootKey.chainCode
            self.depth = 0
            self.parentFingerprint = Data(repeating: 0, count: 4)
            self.childNumber = 0
        }
        
        private init(privateKey: Data, chainCode: Data, depth: UInt8, parentFingerprint: Data, childNumber: UInt32) {
            self.privateKey = privateKey
            self.chainCode = chainCode
            self.depth = depth
            self.parentFingerprint = parentFingerprint
            self.childNumber = childNumber
        }
    }
}

extension PrivateKey.Extended: CustomDebugStringConvertible {
    var debugDescription: String {
        return """
        ExtendedPrivateKey(
            privateKey: \(privateKey.hexadecimalString),
            chainCode: \(chainCode.hexadecimalString),
            depth: \(depth),
            parentFingerprint: \(parentFingerprint.hexadecimalString),
            childNumber: \(childNumber)
        )
        """
    }
}

extension PrivateKey.Extended {
    func deriveChildPrivateKey(at index: UInt32) throws -> PrivateKey.Extended {
        let parentPrivateKey = self.privateKey
        let parentPublicKey = try PublicKey(privateKey: .init(data: privateKey)).compressedData
        
        var data = Data()
        
        let hardened = (index >= 0x80000000)
        switch hardened {
        case false:
            data.append(parentPublicKey)
        case true:
            data.append(Data([0x00]))
            data.append(parentPrivateKey)
        }
        data.append(index.bigEndianData)
        
        let hmac = HMACSHA512.hash(data: data, key: chainCode)
        let leftHMACPart = Data(hmac.prefix(32))
        let rightHMACPart = Data(hmac.suffix(32))
        
        let leftHMACPartBigUInt = BigUInt(leftHMACPart)
        
        let childPrivateKey = ((BigUInt(privateKey) + leftHMACPartBigUInt) % ECDSA.numberOfPointsOnTheCurveWeCanHit).serialize()
        let paddedChildPrivateKey = (childPrivateKey.count < 32) ? (Data(repeating: 0, count: 32 - childPrivateKey.count) + childPrivateKey) : childPrivateKey
        let childChainCode = rightHMACPart
        let childDepth = depth + 1
        let childParentFingerprint = Data(HASH160.hash(data: parentPublicKey).prefix(4))
        let childNumber = index
        
        return .init(privateKey: paddedChildPrivateKey, chainCode: childChainCode, depth: childDepth, parentFingerprint: childParentFingerprint, childNumber: childNumber)
    }
    
    func deriveChild(at path: DerivationPath) throws -> PrivateKey.Extended {
        var extendedKey = self
        
        let indices = [
            path.purpose.index,
            path.coinType.index,
            path.account.index,
            path.usage.index,
            path.index
        ]
        
        for index in indices {
            extendedKey = try extendedKey.deriveChildPrivateKey(at: index)
        }
        
        return extendedKey
    }
}

extension PrivateKey.Extended {
    var address: String {
        var data = Data()
        
        let version = UInt32(0x0488ade4.littleEndian) // Version for xprv
        data.append(version.bigEndianData)
        data.append(Data([depth]))
        data.append(parentFingerprint)
        data.append(childNumber.bigEndianData)
        data.append(chainCode)
        data.append(Data([0x00]) + privateKey)
        
        let checksum = HASH256.hash(data).prefix(4)
        data.append(checksum)
        
        return Base58.encode(data)
    }
}

extension PrivateKey.Extended: Equatable {}
