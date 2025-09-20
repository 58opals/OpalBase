import Foundation
import Testing
@testable import OpalBase

@Suite("Block Header Chain Tests")
struct BlockHeaderChainTests {}

extension BlockHeaderChainTests {
    enum MiningError: Swift.Error {
        case nonceSearchFailed
    }
}

extension BlockHeaderChainTests {
    static func createGenesisHeader() throws -> Block.Header {
        return Block.Header(
            version: 1,
            previousBlockHash: Data(repeating: 0, count: 32),
            merkleRoot: try Data(hexString: "3ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a"),
            time: 1231006505,
            bits: 0x1d00ffff,
            nonce: 2083236893
        )
    }
    
    static func mineHeader(previousHash: Data,
                           merkleSeed: UInt8,
                           time: UInt32,
                           bits: UInt32 = 0x207fffff) throws -> Block.Header {
        var nonce: UInt32 = 0
        while nonce < .max {
            let merkleRoot = Data(repeating: merkleSeed, count: 32)
            let header = Block.Header(
                version: 1,
                previousBlockHash: previousHash,
                merkleRoot: merkleRoot,
                time: time,
                bits: bits,
                nonce: nonce
            )
            
            if header.satisfiesProofOfWork() {
                return header
            }
            
            nonce &+= 1
        }
        
        throw MiningError.nonceSearchFailed
    }
}

extension BlockHeaderChainTests {
    @Test static func testValidGenesisPoW() async throws {
        let header = try createGenesisHeader()
        let genesisHash = HASH256.hash(header.encode())
        let chain = Block.Header.Chain(checkpointHeight: 0, checkpointHash: genesisHash)
        
        try await chain.append(header, height: 0)
        #expect(await chain.latestHeight == 0, "Genesis header should be accepted")
    }
    
    @Test static func testInvalidPoWFails() async throws {
        let base = try createGenesisHeader()
        let invalidHeader = Block.Header(version: base.version,
                                         previousBlockHash: base.previousBlockHash,
                                         merkleRoot: base.merkleRoot,
                                         time: base.time,
                                         bits: base.bits,
                                         nonce: 0)
        let invalidGenesisHash = HASH256.hash(invalidHeader.encode())
        let invalidChain = Block.Header.Chain(checkpointHeight: 0, checkpointHash: invalidGenesisHash)
        
        do {
            try await invalidChain.append(invalidHeader, height: 0)
            #expect(Bool(false), "Invalid PoW not detected")
        } catch Block.Header.Chain.Error.invalidProofOfWork {
            #expect(true, "Invalid PoW caught")
        }
    }
    
    @Test static func testVerifyInclusion() async throws {
        let header = try createGenesisHeader()
        let genesisHash = HASH256.hash(header.encode())
        let chain = Block.Header.Chain(checkpointHeight: 0, checkpointHash: genesisHash)
        try await chain.append(header, height: 0)
        let transactionHash = header.merkleRoot
        let verified = await chain.verifyTransaction(hash: .init(dataFromRPC: transactionHash), merkleProof: [], index: 0, height: 0)
        #expect(verified, "Transaction should be included in genesis block")
    }
    
    @Test static func testHeightContinuityEnforced() async throws {
        let header = try createGenesisHeader()
        let genesisHash = HASH256.hash(header.encode())
        let chain = Block.Header.Chain(checkpointHeight: 0, checkpointHash: genesisHash)
        try await chain.append(header, height: 0)
        
        let firstFollowUp = try mineHeader(previousHash: genesisHash, merkleSeed: 0x01, time: header.time &+ 600)
        try await chain.append(firstFollowUp, height: 1)
        
        let firstFollowUpHash = firstFollowUp.proofOfWorkHash
        let skippedHeightHeader = try mineHeader(previousHash: firstFollowUpHash, merkleSeed: 0x02, time: firstFollowUp.time &+ 600)
        
        do {
            try await chain.append(skippedHeightHeader, height: 3)
            #expect(Bool(false), "Appending out-of-order height should fail")
        } catch Block.Header.Chain.Error.doesNotConnect(let failedHeight) {
            #expect(failedHeight == 3)
        }
        
        let events = await chain.drainMaintenanceEvents()
        let requiresResync = events.contains { event in
            if case .requiresResynchronization(let checkpoint) = event {
                return checkpoint.height == 1 && checkpoint.hash == firstFollowUpHash
            }
            return false
        }
        
        #expect(requiresResync, "Continuity break should request resync from last checkpoint")
    }
    
    @Test static func testTipFreshnessAssessment() async throws {
        let header = try createGenesisHeader()
        let genesisHash = HASH256.hash(header.encode())
        let chain = Block.Header.Chain(checkpointHeight: 0, checkpointHash: genesisHash)
        try await chain.append(header, height: 0)
        
        let staleHeader = try mineHeader(previousHash: genesisHash, merkleSeed: 0x03, time: 1)
        try await chain.append(staleHeader, height: 1)
        
        let observationDate = Date(timeIntervalSince1970: 3600)
        let status = await chain.assessTipFreshness(now: observationDate, tolerance: 300)
        
        switch status.condition {
        case .stale(let drift):
            #expect(drift > 300)
        default:
            #expect(Bool(false), "Stale header should be reported")
        }
        
        let alerts = await chain.drainMaintenanceEvents()
        let staleAlert = alerts.contains { event in
            if case .staleTip(let tipStatus) = event {
                return tipStatus.height == 1
            }
            return false
        }
        
        #expect(staleAlert, "Stale detection should raise an alert")
    }
    
    @Test static func testResetToCheckpointAllowsRecovery() async throws {
        let header = try createGenesisHeader()
        let genesisHash = HASH256.hash(header.encode())
        let chain = Block.Header.Chain(checkpointHeight: 0, checkpointHash: genesisHash)
        try await chain.append(header, height: 0)
        
        let firstFollowUp = try mineHeader(previousHash: genesisHash, merkleSeed: 0x10, time: header.time &+ 600)
        try await chain.append(firstFollowUp, height: 1)
        let firstHash = firstFollowUp.proofOfWorkHash
        
        let secondFollowUp = try mineHeader(previousHash: firstHash, merkleSeed: 0x11, time: firstFollowUp.time &+ 600)
        try await chain.append(secondFollowUp, height: 2)
        
        let checkpoint = Block.Header.Chain.Checkpoint(height: 1, hash: firstHash)
        try await chain.reset(to: checkpoint)
        #expect(await chain.latestHeight == 1)
        
        let replacement = try mineHeader(previousHash: checkpoint.hash, merkleSeed: 0x12, time: firstFollowUp.time &+ 1200)
        try await chain.append(replacement, height: 2)
        
        #expect(await chain.latestHeight == 2)
    }
}
