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
        
        static func raw(_ data: Data) -> Message {
            .init(representation: .payload(data: data, hashRounds: 0))
        }
        
        static func singleSHA256(_ data: Data) -> Message {
            .init(representation: .payload(data: data, hashRounds: 1))
        }
        
        static func doubleSHA256(_ data: Data) -> Message {
            .init(representation: .payload(data: data, hashRounds: 2))
        }
        
        static func hashing(_ data: Data, rounds: UInt8) throws -> Message {
            guard rounds > 0 else { throw Error.hashCountMustBeGreaterThanZero }
            return .init(representation: .payload(data: data, hashRounds: rounds))
        }
        
        static func digest(_ digest: CryptoKit.SHA256.Digest, hashCount: UInt8 = 1) -> Message {
            .init(representation: .digest(digest: digest, hashRounds: hashCount))
        }
    }
}
