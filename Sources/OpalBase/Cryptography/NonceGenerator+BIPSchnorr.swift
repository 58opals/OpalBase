// NonceGenerator+BIPSchnorr.swift

import Foundation
import CryptoKit

extension NonceGenerator {
    struct BIPSchnorr {
        private let privateKeyData: Data
        private let digestData: Data
        private var counter: UInt32 = 0
        
        init(privateKey: Scalar, digest32: Data) throws {
            guard digest32.count == 32 else {
                throw ChallengeHash.Error.invalidDigestLength(actual: digest32.count)
            }
            privateKeyData = privateKey.data32
            digestData = digest32
        }
        
        mutating func makeNextScalar() throws -> Scalar {
            while true {
                var input = Data()
                input.append(privateKeyData)
                input.append(digestData)
                
                if counter != 0 {
                    var counterBigEndian = counter.bigEndian
                    withUnsafeBytes(of: &counterBigEndian) { raw in
                        input.append(contentsOf: raw.bindMemory(to: UInt8.self))
                    }
                }
                counter &+= 1
                
                let hashData = Data(SHA256.hash(input))
                let hashValue = try UInt256(data32: hashData)
                
                var reducedValue = hashValue
                if reducedValue.compare(to: Secp256k1.Constant.n) != .orderedAscending {
                    reducedValue = reducedValue.subtract(Secp256k1.Constant.n).difference
                }
                
                let scalar = Scalar(unchecked: reducedValue)
                guard !scalar.isZero else { continue }
                return scalar
            }
        }
    }
}
