// OpalBase+Block+Header+ChainActor+Checkpoint.swift

import Foundation

extension _OpalBase.Block.Header.ChainActor {
    struct Checkpoint: Equatable, Sendable {
        public let height: UInt32
        public let hash: Data
        
        public init(height: UInt32, hash: Data) {
            self.height = height
            self.hash = hash
        }
    }
}

extension _OpalBase.Block.Header.ChainActor.Checkpoint {
    static var defaultCheckpoint: OpalBase.Block.Header.ChainActor.Checkpoint {
        let hashHexadecimalString = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        let hash = (try? Data(hexadecimalString: hashHexadecimalString))?.reversedData ?? Data(repeating: 0, count: 32)
        return .init(height: 0, hash: hash)
    }
}
