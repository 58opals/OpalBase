// CashCodeDerivation.swift

import Foundation

enum CashCodeDerivation {
    static let childIndex: UInt32 = 0

    static func makeSharedPointDigest(
        signingKey: OpalBase.Key.SigningKey,
        publicKey: OpalBase.Key.PublicKey
    ) throws -> Data {
        let xCoordinate = try OpalCryptoAdapter
            .deriveSharedPointXCoordinate(
                signingKey: signingKey,
                publicKey: publicKey
            )
        guard xCoordinate.count == 32 else {
            throw OpalBase.ReusablePaymentAddress.Error.invalidDerivationDigest
        }
        return OpalCryptoAdapter.sha256(Data([0]) + xCoordinate)
    }

    static func makeOutpointText(
        _ outpoint: OpalBase.Transaction.Outpoint
    ) throws -> String {
        guard outpoint.transactionHash.reverseOrder.count
            == OpalBase.Transaction.Hash.expectedByteCount
        else {
            throw OpalBase.ReusablePaymentAddress.Error.invalidOutpointTransactionHash
        }
        return outpoint.transactionHash.reverseOrder.hexadecimalString
            + String(outpoint.outputIndex)
    }

    static func makeOutpointHash(
        _ outpoint: OpalBase.Transaction.Outpoint
    ) throws -> Data {
        let text = try makeOutpointText(outpoint)
        return OpalCryptoAdapter.sha256(Data(text.utf8))
    }

    static func makeMinimalUnsignedSum(
        _ left: Data,
        _ right: Data
    ) throws -> Data {
        guard left.count == 32, right.count == 32 else {
            throw OpalBase.ReusablePaymentAddress.Error.invalidDerivationDigest
        }

        let leftBytes = [UInt8](left)
        let rightBytes = [UInt8](right)
        var result = [UInt8](repeating: 0, count: 33)
        var carry: UInt16 = 0

        for offset in 0..<32 {
            let index = 31 - offset
            let total = UInt16(leftBytes[index])
                + UInt16(rightBytes[index])
                + carry
            result[index + 1] = UInt8(total & 0xff)
            carry = total >> 8
        }
        result[0] = UInt8(carry)

        let firstNonzeroIndex = result.firstIndex { $0 != 0 }
        return firstNonzeroIndex.map { Data(result[$0...]) } ?? Data()
    }

    static func makeChainCode(
        sharedPointDigest: Data,
        outpoint: OpalBase.Transaction.Outpoint
    ) throws -> Data {
        let outpointHash = try makeOutpointHash(outpoint)
        let sum = try makeMinimalUnsignedSum(
            sharedPointDigest,
            outpointHash
        )
        return OpalCryptoAdapter.sha256(sum)
    }

    static func derivePublicKey(
        from parentPublicKey: OpalBase.Key.PublicKey,
        sharedPointDigest: Data,
        outpoint: OpalBase.Transaction.Outpoint
    ) throws -> OpalBase.Key.PublicKey {
        let chainCode = try makeChainCode(
            sharedPointDigest: sharedPointDigest,
            outpoint: outpoint
        )
        return try OpalCryptoAdapter.deriveNonHardenedChildPublicKey(
            from: parentPublicKey,
            chainCode: chainCode,
            at: childIndex
        )
    }

    static func deriveSigningKey(
        from parentSigningKey: OpalBase.Key.SigningKey,
        sharedPointDigest: Data,
        outpoint: OpalBase.Transaction.Outpoint
    ) throws -> OpalBase.Key.SigningKey {
        let chainCode = try makeChainCode(
            sharedPointDigest: sharedPointDigest,
            outpoint: outpoint
        )
        return try OpalCryptoAdapter.deriveNonHardenedChildSigningKey(
            from: parentSigningKey,
            chainCode: chainCode,
            at: childIndex
        )
    }

    static func makeLockingScript(
        for publicKey: OpalBase.Key.PublicKey
    ) -> Data {
        OpalBase.Script.p2pkh_OPCHECKSIG(
            hash: .init(publicKey: publicKey)
        ).data
    }
}
