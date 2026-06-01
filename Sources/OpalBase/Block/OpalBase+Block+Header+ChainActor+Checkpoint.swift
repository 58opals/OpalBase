// OpalBase+Block+Header+ChainActor+Checkpoint.swift

import Foundation

extension _OpalBase.Block.Header.ChainActor {
    struct Checkpoint: Equatable, Sendable {
        let height: UInt32
        let hash: Data
        
        init(height: UInt32, hash: Data) {
            self.height = height
            self.hash = Data(hash)
        }
    }
}

extension _OpalBase.Block.Header.ChainActor.Checkpoint {
    static var defaultCheckpoint: OpalBase.Block.Header.ChainActor.Checkpoint {
        let genesisHashHexadecimal = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        guard let hash = try? Data(hexadecimalString: genesisHashHexadecimal).reversedData else {
            preconditionFailure("Invalid default checkpoint hash.")
        }
        return .init(height: 0, hash: hash)
    }
}
