// PrivateKey+Extended.swift

import Foundation

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

        init(privateKey: Data, chainCode: Data, depth: UInt8, parentFingerprint: Data, childIndexNumber: UInt32) {
            self.privateKey = privateKey
            self.chainCode = chainCode
            self.depth = depth
            self.parentFingerprint = parentFingerprint
            self.childIndexNumber = childIndexNumber
        }

        init(xprv: String) throws {
            guard let data = Base58.decode(xprv) else { throw Error.invalidFormat }
            guard data.count == 82 else { throw Error.invalidLength }

            let payload = data.prefix(data.count - 4)
            let checksum = data.suffix(4)
            let computedChecksum = HASH256.computeChecksum(for: payload)
            guard checksum.elementsEqual(computedChecksum) else { throw Error.invalidChecksum }

            let version = payload[0..<4].withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
            guard version == 0x0488ade4 else { throw Error.invalidVersion } // xprv main-net

            self.depth = payload[4]
            self.parentFingerprint = Data(payload[5..<9])
            self.childIndexNumber = payload[9..<13].withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
            self.chainCode = Data(payload[13..<45])

            guard payload[45] == 0 else { throw Error.invalidKeyPrefix }
            self.privateKey = Data(payload[46..<78])
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

extension PrivateKey.Extended: Sendable {}
extension PrivateKey.Extended: Equatable {}
