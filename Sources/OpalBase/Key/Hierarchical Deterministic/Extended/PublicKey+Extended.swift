// PublicKey+Extended.swift

import Foundation
import BigInt

extension PublicKey {
    public struct Extended {
        let publicKey: Data
        let chainCode: Data
        let depth: UInt8
        let parentFingerprint: Data
        let childIndexNumber: UInt32
        
        public init(publicKey: Data, chainCode: Data, depth: UInt8, parentFingerprint: Data, childIndexNumber: UInt32) {
            self.publicKey = publicKey
            self.chainCode = chainCode
            self.depth = depth
            self.parentFingerprint = parentFingerprint
            self.childIndexNumber = childIndexNumber
        }
        
        public init(xpub: String) throws {
            guard let data = Base58.decode(xpub) else { throw Error.invalidFormat }
            guard data.count == 82 else { throw Error.invalidLength }
            let version = UInt32(bigEndian: data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self) })
            guard version == 0x0488b21e else { throw Error.invalidVersion }
            self.depth = data[4]
            self.parentFingerprint = Data(data[5..<9])
            self.childIndexNumber = UInt32(bigEndian: data[9..<13].withUnsafeBytes { $0.load(as: UInt32.self) })
            self.chainCode = Data(data[13..<45])
            self.publicKey = Data(data[45..<78])
        }
        
        public init(extendedPrivateKey: PrivateKey.Extended) throws {
            self.publicKey = try PublicKey(privateKey: .init(data: extendedPrivateKey.privateKey)).compressedData
            self.chainCode = extendedPrivateKey.chainCode
            self.depth = extendedPrivateKey.depth
            self.parentFingerprint = extendedPrivateKey.parentFingerprint
            self.childIndexNumber = extendedPrivateKey.childIndexNumber
        }
    }
}

extension PublicKey.Extended: Hashable {
    public static func == (lhs: PublicKey.Extended, rhs: PublicKey.Extended) -> Bool {
        lhs.publicKey == rhs.publicKey &&
        lhs.chainCode == rhs.chainCode &&
        lhs.depth == rhs.depth &&
        lhs.parentFingerprint == rhs.parentFingerprint &&
        lhs.childIndexNumber == rhs.childIndexNumber
    }
}

extension PublicKey.Extended: CustomDebugStringConvertible {
    public var debugDescription: String {
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

extension PublicKey.Extended {
    private func deriveChildPublicKey(at index: UInt32) throws -> PublicKey.Extended {
        let hardened = (index >= 0x80000000)
        print(index)
        print(index.data.hexadecimalString)
        guard !hardened else { throw PublicKey.Error.hardenedDerivation }
        
        var data = Data()
        
        data.append(publicKey)
        data.append(index.bigEndianData)
        
        let hmac = HMACSHA512.hash(data, key: chainCode)
        let leftHMACPart = Data(hmac.prefix(32))
        let rightHMACPart = Data(hmac.suffix(32))
        
        let leftHMACPartBigUInt = BigUInt(leftHMACPart)
        guard leftHMACPartBigUInt != 0 && leftHMACPartBigUInt < ECDSA.numberOfPointsOnTheCurveWeCanHit else { throw PublicKey.Error.publicKeyDerivationFailed }
        
        let childPublicKey = try ECDSA.add(to: publicKey, tweak: leftHMACPart)
        let childChainCode = rightHMACPart
        let childDepth = depth + 1
        let childParentFingerprint = Data(HASH160.hash(publicKey).prefix(4))
        let childIndexNumber = index
        
        return .init(publicKey: childPublicKey, chainCode: childChainCode, depth: childDepth, parentFingerprint: childParentFingerprint, childIndexNumber: childIndexNumber)
    }
    
    func deriveChild(at path: DerivationPath) throws -> PublicKey.Extended {
        var extendedKey = self
        
        let indices = [
            path.purpose.hardenedIndex,
            path.coinType.hardenedIndex,
            try path.account.getHardenedIndex(),
            path.usage.unhardenedIndex,
            path.index
        ]
        
        for index in indices {
            extendedKey = try extendedKey.deriveChildPublicKey(at: index)
        }
        
        return extendedKey
    }
}

extension PublicKey.Extended {
    public var address: String {
        Base58.encode(serialize())
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
        let checksum = HASH256.hash(data).prefix(4)
        data.append(checksum)
        return data
    }
}

extension PublicKey.Extended: Equatable {}
extension PublicKey.Extended: Sendable {}
