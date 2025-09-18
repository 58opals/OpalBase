import Foundation
import Testing
@testable import OpalBase

@Suite("Block Header Chain Tests")
struct BlockHeaderChainTests {}

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
}
