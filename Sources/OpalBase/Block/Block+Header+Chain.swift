// Block+Header+Chain.swift

import Foundation
import BigInt

extension Block.Header {
    actor Chain {
        private let checkpointHeight: UInt32
        private let checkpointHash: Data
        private let maxCheckpointDepth: Int
        
        private var headers: [UInt32: Block.Header] = .init()
        private var hashes: [UInt32: Data] = .init()
        private var checkpoints: [Checkpoint]
        private var tipHeight: UInt32
        private var tipHash: Data
        
        private var tipTimestamp: UInt32?
        private var queuedMaintenanceEvents: [MaintenanceEvent] = .init()
        private var lastTipStatus: TipStatus?
        
        init(checkpointHeight: UInt32, checkpointHash: Data, maxCheckpointDepth: Int = 24) {
            self.checkpointHeight = checkpointHeight
            self.checkpointHash = checkpointHash
            self.maxCheckpointDepth = max(1, maxCheckpointDepth)
            self.checkpoints = [.init(height: checkpointHeight, hash: checkpointHash)]
            self.tipHeight = checkpointHeight
            self.tipHash = checkpointHash
        }
    }
}

extension Block.Header.Chain {
    enum Error: Swift.Error {
        case invalidProofOfWork(height: UInt32)
        case doesNotConnect(height: UInt32)
        case checkpointViolation(expected: Checkpoint, actual: Checkpoint?)
    }
}
