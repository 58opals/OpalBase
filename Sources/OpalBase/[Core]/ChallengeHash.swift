// ChallengeHash.swift

import Foundation
import CryptoKit

enum ChallengeHash {
    enum Error: Swift.Error, Equatable {
        case invalidDigestLength(actual: Int)
    }
    
    static func makeChallengeScalar(
        digest32: Data,
        r: FieldElement,
        publicKey: AffinePoint
    ) throws -> Scalar {
        guard digest32.count == 32 else {
            throw Error.invalidDigestLength(actual: digest32.count)
        }
        let publicKeyData = publicKey.compressedEncoding33()
        let rData = r.data32
        var input = Data()
        input.append(rData)
        input.append(publicKeyData)
        input.append(digest32)
        let hashData = Data(SHA256.hash(input))
        let hashValue = try UInt256(data32: hashData)
        var reducedValue = hashValue
        if reducedValue.compare(to: Secp256k1.Constant.n) != .orderedAscending {
            reducedValue = reducedValue.subtracting(Secp256k1.Constant.n).difference
        }
        return Scalar(unchecked: reducedValue)
    }
}
