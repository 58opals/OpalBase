// PrivateKey+Extended.swift

import Foundation
import BigInt

extension PrivateKey {
    public struct Extended {
        let privateKey: Data
        let chainCode: Data
        let depth: UInt8
        let parentFingerprint: Data
        let childNumber: UInt32
        
        public init(rootKey: PrivateKey.Extended.Root) {
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

extension PrivateKey.Extended: Hashable {
    public static func == (lhs: PrivateKey.Extended, rhs: PrivateKey.Extended) -> Bool {
        lhs.privateKey == rhs.privateKey &&
        lhs.chainCode == rhs.chainCode &&
        lhs.depth == rhs.depth &&
        lhs.parentFingerprint == rhs.parentFingerprint &&
        lhs.childNumber == rhs.childNumber
    }
}

extension PrivateKey.Extended: CustomDebugStringConvertible {
    public var debugDescription: String {
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
    private func deriveChildPrivateKey(at index: UInt32) throws -> PrivateKey.Extended {
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
        
        let hmac = HMACSHA512.hash(data, key: chainCode)
        let leftHMACPart = Data(hmac.prefix(32))
        let rightHMACPart = Data(hmac.suffix(32))
        
        let leftHMACPartBigUInt = BigUInt(leftHMACPart)
        
        let childPrivateKey = ((BigUInt(privateKey) + leftHMACPartBigUInt) % ECDSA.numberOfPointsOnTheCurveWeCanHit).serialize()
        let paddedChildPrivateKey = (childPrivateKey.count < 32) ? (Data(repeating: 0, count: 32 - childPrivateKey.count) + childPrivateKey) : childPrivateKey
        let childChainCode = rightHMACPart
        let childDepth = depth + 1
        let childParentFingerprint = Data(HASH160.hash(parentPublicKey).prefix(4))
        let childNumber = index
        
        return .init(privateKey: paddedChildPrivateKey, chainCode: childChainCode, depth: childDepth, parentFingerprint: childParentFingerprint, childNumber: childNumber)
    }
    
    func deriveChild(at path: DerivationPath) throws -> PrivateKey.Extended {
        var extendedKey = self
        
        let indices = try [
            path.purpose.hardenedIndex,
            path.coinType.hardenedIndex,
            path.account.getHardenedIndex(),
            path.usage.unhardenedIndex,
            path.index
        ]
        
        for index in indices {
            extendedKey = try extendedKey.deriveChildPrivateKey(at: index)
        }
        
        return extendedKey
    }
}

extension PrivateKey.Extended {
    public var address: String {
        return Base58.encode(serialize())
    }
    
    func serialize() -> Data {
        var data = Data()
        let version = UInt32(0x0488ade4.littleEndian)
        data.append(version.bigEndianData)
        data.append(Data([self.depth]))
        data.append(self.parentFingerprint)
        data.append(self.childNumber.bigEndianData)
        data.append(self.chainCode)
        data.append(Data([0x00]) + self.privateKey)
        let checksum = HASH256.hash(data).prefix(4)
        data.append(checksum)
        
        return data
    }
}

extension PrivateKey.Extended: Equatable {}
extension PrivateKey.Extended: Sendable {}
