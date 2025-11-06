// PrivateKey+Extended.swift

import Foundation
import BigInt

extension PrivateKey {
    struct Extended {
        let privateKey: Data
        let chainCode: Data
        let depth: UInt8
        let parentFingerprint: Data
        let childIndexNumber: UInt32
        
        init(rootKey: PrivateKey.Extended.Root) {
            self.privateKey = rootKey.privateKey
            self.chainCode = rootKey.chainCode
            self.depth = 0
            self.parentFingerprint = Data(repeating: 0, count: 4)
            self.childIndexNumber = 0
        }
        
        private init(privateKey: Data, chainCode: Data, depth: UInt8, parentFingerprint: Data, childIndexNumber: UInt32) {
            self.privateKey = privateKey
            self.chainCode = chainCode
            self.depth = depth
            self.parentFingerprint = parentFingerprint
            self.childIndexNumber = childIndexNumber
        }
        
        init(xprv: String) throws {
            guard let data = Base58.decode(xprv) else { throw Error.invalidFormat }
            guard data.count == 82 else { throw Error.invalidLength }
            let version = data[0..<4].withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
            guard version == 0x0488ade4 else { throw Error.invalidVersion } // xprv main‑net
            self.depth = data[4]
            self.parentFingerprint = Data(data[5..<9])
            self.childIndexNumber = data[9..<13].withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
            self.chainCode = Data(data[13..<45])
            
            guard data[45] == 0 else { throw Error.invalidKeyPrefix }
            self.privateKey = Data(data[46..<78])
        }
    }
}

extension PrivateKey.Extended: Hashable {
    static func == (lhs: PrivateKey.Extended, rhs: PrivateKey.Extended) -> Bool {
        lhs.privateKey == rhs.privateKey &&
        lhs.chainCode == rhs.chainCode &&
        lhs.depth == rhs.depth &&
        lhs.parentFingerprint == rhs.parentFingerprint &&
        lhs.childIndexNumber == rhs.childIndexNumber
    }
}

extension PrivateKey.Extended: CustomDebugStringConvertible {
    var debugDescription: String {
        """
        ExtendedPrivateKey(
            privateKey: \(privateKey.hexadecimalString),
            chainCode: \(chainCode.hexadecimalString),
            depth: \(depth),
            parentFingerprint: \(parentFingerprint.hexadecimalString),
            childIndexNumber: \(childIndexNumber)
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
        let childIndexNumber = index
        
        return .init(privateKey: paddedChildPrivateKey, chainCode: childChainCode, depth: childDepth, parentFingerprint: childParentFingerprint, childIndexNumber: childIndexNumber)
    }
    
    func deriveChild(at path: DerivationPath) throws -> PrivateKey.Extended {
        try deriveChild(at: path.makeIndices())
    }
    
    func deriveChild(at indices: [UInt32]) throws -> PrivateKey.Extended {
        var extendedKey = self
        let startingDepth = Int(self.depth)
        
        for index in indices.dropFirst(startingDepth) {
            extendedKey = try extendedKey.deriveChildPrivateKey(at: index)
        }
        
        return extendedKey
    }
}

extension PrivateKey.Extended {
    func deriveExtendedPublicKey() throws -> PublicKey.Extended { try .init(extendedPrivateKey: self) }
    
    func deriveChildPublicKey(at path: DerivationPath) throws -> PublicKey.Extended {
        let child = try deriveChild(at: path)
        return try .init(extendedPrivateKey: child)
    }
}

extension PrivateKey.Extended {
    var address: String {
        return Base58.encode(serialize())
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
        let checksum = HASH256.hash(data).prefix(4)
        data.append(checksum)
        
        return data
    }
}

extension PrivateKey.Extended: Equatable {}
extension PrivateKey.Extended: Sendable {}
