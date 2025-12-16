// Block+Header+Chain.swift

import Foundation
import BigInt

extension Block.Header {
    public actor Chain {
        public struct UpdateResult: Sendable {
            let detachedHeights: [UInt32]
            let newTip: Checkpoint
        }
        
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
            self.hashes[checkpointHeight] = checkpointHash
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

extension Block.Header.Chain {
    func currentTip() -> Checkpoint {
        Checkpoint(height: tipHeight, hash: tipHash)
    }
    
    func knownHash(at height: UInt32) -> Data? {
        hashes[height]
    }
    
    func knownHeader(at height: UInt32) -> Block.Header? {
        headers[height]
    }
    
    func updateTipStatus(now: Date,
                         staleInterval: TimeInterval = 2 * 60 * 60,
                         futureDriftTolerance: TimeInterval = 10 * 60) {
        guard let tipTimestamp else { return }
        let headerTime = Date(timeIntervalSince1970: TimeInterval(tipTimestamp))
        let drift = now.timeIntervalSince(headerTime)
        
        let condition: TipStatus.Condition
        if drift > staleInterval {
            condition = .stale(by: drift)
        } else if drift < -futureDriftTolerance {
            condition = .future(by: -drift)
        } else {
            condition = .fresh
        }
        
        let status = TipStatus(condition: condition,
                               headerTime: headerTime,
                               assessedAt: now,
                               height: tipHeight)
        
        guard lastTipStatus != status else { return }
        lastTipStatus = status
        
        if case .stale = condition {
            queuedMaintenanceEvents.append(.staleTip(status: status))
        }
    }
    
    func dequeueMaintenanceEvents() -> [MaintenanceEvent] {
        guard !queuedMaintenanceEvents.isEmpty else { return .init() }
        let events = queuedMaintenanceEvents
        queuedMaintenanceEvents.removeAll()
        return events
    }
    
    func apply(header: Block.Header, at height: UInt32) throws -> UpdateResult {
        guard header.isProofOfWorkSatisfied else { throw Error.invalidProofOfWork(height: height) }
        let headerHash = header.proofOfWorkHash
        
        if height == checkpointHeight {
            guard headerHash == checkpointHash else {
                throw Error.checkpointViolation(expected: .init(height: checkpointHeight, hash: checkpointHash),
                                                actual: .init(height: height, hash: headerHash))
            }
        }
        
        if let existingHash = hashes[height], existingHash == headerHash {
            headers[height] = header
            if height >= tipHeight {
                tipTimestamp = header.time
            }
            return UpdateResult(detachedHeights: .init(), newTip: currentTip())
        }
        
        var detachedHeights: [UInt32] = .init()
        
        if height <= tipHeight {
            if let existingHash = hashes[height], existingHash != headerHash {
                detachedHeights = Array(height...tipHeight)
                for oldHeight in detachedHeights {
                    headers.removeValue(forKey: oldHeight)
                    hashes.removeValue(forKey: oldHeight)
                }
                let newTipHeight = height == 0 ? 0 : height &- 1
                let nextHash = hashes[newTipHeight] ?? (newTipHeight == checkpointHeight ? checkpointHash : nil)
                tipHeight = newTipHeight
                tipHash = nextHash ?? checkpointHash
                checkpoints.removeAll { $0.height >= height }
                queuedMaintenanceEvents.append(.requiresResynchronization(from: .init(height: height, hash: headerHash)))
            }
        } else if height > tipHeight + 1, hashes[height - 1] == nil {
            headers.removeAll()
            hashes.removeAll()
            hashes[checkpointHeight] = checkpointHash
            checkpoints = [Checkpoint(height: checkpointHeight, hash: checkpointHash)]
            tipHeight = checkpointHeight
            tipHash = checkpointHash
            queuedMaintenanceEvents.append(.requiresResynchronization(from: .init(height: height, hash: headerHash)))
        }
        
        if height > checkpointHeight, let previousHash = hashes[height - 1] {
            guard previousHash == header.previousBlockHash else {
                throw Error.doesNotConnect(height: height)
            }
        }
        
        headers[height] = header
        hashes[height] = headerHash
        
        if height >= tipHeight {
            tipHeight = height
            tipHash = headerHash
            tipTimestamp = header.time
        }
        
        checkpoints.removeAll { $0.height == height }
        checkpoints.append(.init(height: height, hash: headerHash))
        if checkpoints.count > maxCheckpointDepth {
            let overflow = checkpoints.count - maxCheckpointDepth
            checkpoints.removeFirst(overflow)
            if checkpoints.first?.height != checkpointHeight {
                checkpoints.insert(.init(height: checkpointHeight, hash: checkpointHash), at: 0)
            }
        }
        
        return UpdateResult(detachedHeights: detachedHeights, newTip: currentTip())
    }
}
