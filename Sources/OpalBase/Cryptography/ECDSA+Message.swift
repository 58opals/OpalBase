// ECDSA+Message.swift

import Foundation
import CryptoKit

extension ECDSA {
    struct Message {
        enum Error: Swift.Error {
            case hashCountMustBeGreaterThanZero
            case invalidDigestByteCount(expected: Int, actual: Int)
        }
        
        private enum Representation {
            case payload(data: Data, hashRounds: UInt8)
            case digest(digest: CryptoKit.SHA256.Digest, hashRounds: UInt8)
        }
        
        private let representation: Representation
        
        private init(representation: Representation) {
            self.representation = representation
        }
    }
}

extension ECDSA.Message {
    static func makeRaw(_ data: Data) -> ECDSA.Message {
        .init(representation: .payload(data: data, hashRounds: 0))
    }
    
    static func makeSingleSHA256(_ data: Data) -> ECDSA.Message {
        .init(representation: .payload(data: data, hashRounds: 1))
    }
    
    static func makeDoubleSHA256(_ data: Data) -> ECDSA.Message {
        .init(representation: .payload(data: data, hashRounds: 2))
    }
    
    static func makeHashing(_ data: Data, rounds: UInt8) throws -> ECDSA.Message {
        guard rounds > 0 else { throw Error.hashCountMustBeGreaterThanZero }
        return .init(representation: .payload(data: data, hashRounds: rounds))
    }
    
    static func makeDigest(_ digest: CryptoKit.SHA256.Digest, hashCount: UInt8 = 1) -> ECDSA.Message {
        .init(representation: .digest(digest: digest, hashRounds: hashCount))
    }
}

extension ECDSA.Message {
    func makeConsensusDigest32() throws -> Data {
        let baseData = dataForHashingRounds()
        let rounds = Int(hashRounds)
        guard rounds > 0 else { throw Error.hashCountMustBeGreaterThanZero }
        let digestData = applyHashRounds(baseData, rounds: rounds)
        guard digestData.count == 32 else {
            throw Error.invalidDigestByteCount(expected: 32, actual: digestData.count)
        }
        return digestData
    }
    
    func makeDataForSignerHashingOnceSHA256Internally() throws -> Data {
        let baseData = dataForHashingRounds()
        let rounds = max(Int(hashRounds) - 1, 0)
        guard rounds > 0 else { return baseData }
        return applyHashRounds(baseData, rounds: rounds)
    }
}

private extension ECDSA.Message {
    var hashRounds: UInt8 {
        switch representation {
        case .payload(_, let rounds):
            return rounds
        case .digest(_, let rounds):
            return rounds
        }
    }
    
    func dataForHashingRounds() -> Data {
        switch representation {
        case .payload(let data, _):
            return data
        case .digest(let digest, _):
            return Data(digest)
        }
    }
    
    func applyHashRounds(_ data: Data, rounds: Int) -> Data {
        var hashedData = data
        for _ in 0..<rounds {
            hashedData = SHA256.hash(hashedData)
        }
        return hashedData
    }
}
