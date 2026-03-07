// ChallengeHashModel.swift

import Foundation
import CryptoKit

enum ChallengeHashModel {
    enum Error: Swift.Error, Equatable {
        case invalidDigestLength(actual: Int)
    }
    
    static func makeChallengeScalar(
        digest32: Data,
        r: FieldElementModel,
        publicKey: AffinePointModel
    ) throws -> ScalarModel {
        guard digest32.count == 32 else {
            throw Error.invalidDigestLength(actual: digest32.count)
        }
        let publicKeyData = publicKey.encodeCompressed33()
        let rData = r.data32
        var input = Data()
        input.append(rData)
        input.append(publicKeyData)
        input.append(digest32)
        let hashData = Data(SHA256Model.hash(input))
        let hashValue = try UInt256Model(data32: hashData)
        var reducedValue = hashValue
        if reducedValue.compare(to: Secp256k1Model.ConstantModel.n) != .orderedAscending {
            reducedValue = reducedValue.subtract(Secp256k1Model.ConstantModel.n).difference
        }
        return ScalarModel(unchecked: reducedValue)
    }
}
