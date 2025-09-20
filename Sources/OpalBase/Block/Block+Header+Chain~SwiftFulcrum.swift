// Block+Header+Chain~SwiftFulcrum.swift

import Foundation
import BigInt
import SwiftFulcrum

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

extension Block.Header.Chain {
    var latestHeight: UInt32 { tipHeight }
    var latestCheckpoint: Checkpoint { checkpoints.last ?? .init(height: tipHeight, hash: tipHash) }
    
    func append(_ header: Block.Header, height: UInt32) throws {
        let headerHash = try verify(header, height: height)
        
        if headers.isEmpty {
            guard height == checkpointHeight else {
                registerContinuityFailure()
                throw Error.doesNotConnect(height: height)
            }
            guard headerHash == checkpointHash else {
                registerContinuityFailure()
                throw Error.doesNotConnect(height: height)
            }
        } else {
            let expectedHeight = tipHeight &+ 1
            guard height == expectedHeight else {
                registerContinuityFailure()
                throw Error.doesNotConnect(height: height)
            }
            guard header.previousBlockHash == tipHash else {
                registerContinuityFailure()
                throw Error.doesNotConnect(height: height)
            }
        }
        
        headers[height] = header
        hashes[height] = headerHash
        tipHeight = height
        tipHash = headerHash
        tipTimestamp = header.time
        lastTipStatus = nil
        registerCheckpoint(height: height, hash: headerHash)
    }
    
    func verifyTransaction(hash: Transaction.Hash, merkleProof: [Data], index: Int, height: UInt32) -> Bool {
        guard let header = headers[height] else { return false }
        
        var currentHash = hash.naturalOrder
        var currentIndex = index
        for sibling in merkleProof {
            if currentIndex % 2 == 0 {
                currentHash = HASH256.hash(currentHash + sibling)
            } else {
                currentHash = HASH256.hash(sibling + currentHash)
            }
            
            currentIndex >>= 1
        }
        
        return currentHash == header.merkleRoot
    }
    
    func sync(from startHeight: UInt32? = nil, using fulcrum: Fulcrum) async throws {
        var height = startHeight ?? (headers.isEmpty ? checkpointHeight : tipHeight &+ 1)
        while true {
            let response = try await fulcrum.submit(method: .blockchain(.block(.header(height: .init(height), checkpointHeight: nil))),
                                                    responseType: Response.Result.Blockchain.Block.Header.self)
            guard case .single(let id, let result) = response else { break }
            await Telemetry.shared.record(
                name: "blockchain.sync.received",
                category: .blockchain,
                message: "Synced block payload",
                metadata: [
                    "block.identifier": .string(id.uuidString),
                    "block.height": .int(Int(height))
                ],
                sensitiveKeys: ["block.identifier"]
            )
            
            let headerData = try Data(hexString: result.hex)
            let (header, bytes) = try Block.Header.decode(from: headerData)
            await Telemetry.shared.record(
                name: "blockchain.sync.decoded",
                category: .blockchain,
                message: "Decoded block header payload",
                metadata: [
                    "block.identifier": .string(id.uuidString),
                    "header.payload": .string(header.encode().hexadecimalString)
                ],
                metrics: [
                    "block.payloadBytes": Double(bytes)
                ],
                sensitiveKeys: ["block.identifier", "header.payload"]
            )
            
            try append(header, height: height)
            height &+= 1
        }
    }
}

extension Block.Header.Chain {
    func reset(to checkpoint: Checkpoint) throws {
        guard checkpoint.height >= checkpointHeight else {
            let baseline = Checkpoint(height: checkpointHeight, hash: checkpointHash)
            throw Error.checkpointViolation(expected: checkpoint, actual: baseline)
        }
        if checkpoint.height == checkpointHeight && checkpoint.hash != checkpointHash {
            let baseline = Checkpoint(height: checkpointHeight, hash: checkpointHash)
            throw Error.checkpointViolation(expected: checkpoint, actual: baseline)
        }
        if let knownHash = hashes[checkpoint.height], knownHash != checkpoint.hash {
            let actual = Checkpoint(height: checkpoint.height, hash: knownHash)
            throw Error.checkpointViolation(expected: checkpoint, actual: actual)
        }
        
        headers = headers.filter { $0.key <= checkpoint.height }
        hashes = hashes.filter { $0.key <= checkpoint.height }
        tipHeight = checkpoint.height
        tipHash = checkpoint.hash
        tipTimestamp = headers[checkpoint.height]?.time
        lastTipStatus = nil
        checkpoints = checkpoints.filter { $0.height <= checkpoint.height }
        if checkpoints.last != checkpoint {
            checkpoints.append(checkpoint)
        }
    }
    
    func drainMaintenanceEvents() -> [MaintenanceEvent] {
        let events = queuedMaintenanceEvents
        queuedMaintenanceEvents.removeAll()
        return events
    }
    
    func assessTipFreshness(now: Date = .init(), tolerance: TimeInterval) -> TipStatus {
        guard let timestamp = tipTimestamp else {
            let status = TipStatus(condition: .fresh, headerTime: .distantPast, assessedAt: now, height: tipHeight)
            lastTipStatus = status
            return status
        }
        
        let headerTime = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let drift = now.timeIntervalSince(headerTime)
        let condition: TipStatus.Condition
        
        if drift > tolerance {
            condition = .stale(by: drift)
        } else if drift < -tolerance {
            condition = .future(by: -drift)
        } else {
            condition = .fresh
        }
        
        let status = TipStatus(condition: condition, headerTime: headerTime, assessedAt: now, height: tipHeight)
        if status.condition != .fresh && status != lastTipStatus {
            queueMaintenanceEvent(.staleTip(status: status))
        }
        lastTipStatus = status
        return status
    }
}

extension Block.Header.Chain {
    private func verify(_ header: Block.Header, height: UInt32) throws -> Data {
        let hash = header.proofOfWorkHash
        let hashNumber = BigUInt(hash.reversedData)
        let target = Block.Header.getTarget(for: header.bits)
        
        guard hashNumber <= target else { throw Error.invalidProofOfWork(height: height) }
        return hash
    }
    
    private func registerCheckpoint(height: UInt32, hash: Data) {
        let checkpoint = Checkpoint(height: height, hash: hash)
        guard checkpoints.last != checkpoint else { return }
        checkpoints.append(checkpoint)
        let overflow = checkpoints.count - maxCheckpointDepth
        if overflow > 0 {
            checkpoints.removeFirst(overflow)
        }
    }
    
    private func registerContinuityFailure() {
        queueMaintenanceEvent(.requiresResynchronization(from: latestCheckpoint))
    }
    
    private func queueMaintenanceEvent(_ event: MaintenanceEvent) {
        guard queuedMaintenanceEvents.contains(event) == false else { return }
        queuedMaintenanceEvents.append(event)
    }
}
