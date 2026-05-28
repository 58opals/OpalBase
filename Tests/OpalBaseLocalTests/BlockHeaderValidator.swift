// BlockHeaderValidator.swift

import Foundation
import OpalCrypto
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Block.Header", .tags(.unit, .block))
struct BlockHeaderValidator {
    @Test("decode rejects insufficient data")
    func decodeRejectsInsufficientData() {
        let validHeader = Data(repeating: 0x01, count: 80)
        let truncatedHeader = Data(validHeader.dropLast())
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try OpalBase.Block.Header.decode(from: truncatedHeader)
        }
    }
    
    @Test("decode round-trips encoded header")
    func decodeRoundTripsEncodedHeader() throws {
        let previousBlockHash = Data(repeating: 0x02, count: 32)
        let merkleRoot = Data(repeating: 0x03, count: 32)
        let header = OpalBase.Block.Header(
            version: 2,
            previousBlockHash: previousBlockHash,
            merkleRoot: merkleRoot,
            time: 1,
            bits: 0x1d00ffff,
            nonce: 4
        )
        
        let encoded = header.encode()
        let (decoded, bytesRead) = try OpalBase.Block.Header.decode(from: encoded)
        
        #expect(bytesRead == encoded.count)
        #expect(decoded.version == header.version)
        #expect(decoded.previousBlockHash == header.previousBlockHash)
        #expect(decoded.merkleRoot == header.merkleRoot)
        #expect(decoded.time == header.time)
        #expect(decoded.bits == header.bits)
        #expect(decoded.nonce == header.nonce)
    }
    
    @Test("proof-of-work hash uses little-endian order")
    func proofOfWorkHashUsesLittleEndianOrder() {
        let header = OpalBase.Block.Header(
            version: 1,
            previousBlockHash: Data(repeating: 0x11, count: 32),
            merkleRoot: Data(repeating: 0x22, count: 32),
            time: 0x12345678,
            bits: 0x1d00ffff,
            nonce: 0x42
        )
        
        let headerEncoding = header.encode()
        let expectedHash = OpalCrypto.Hashing.hash256(headerEncoding).reversedData
        
        #expect(header.proofOfWorkHash == expectedHash)
    }
    
    @Test("calculate target matches known compact value")
    func calculateTargetMatchesKnownCompactValue() throws {
        let bits: UInt32 = 0x1d00ffff
        let expectedTargetData = try Data(hexadecimalString: "00000000ffff0000000000000000000000000000000000000000000000000000")
        let expectedTarget = OpalBase.Block.Target(data: expectedTargetData)
        
        let target = OpalBase.Block.Header.calculateTarget(for: bits)
        
        #expect(target == expectedTarget)
    }
    
    @Test("proof-of-work validation matches known header")
    func proofOfWorkValidationMatchesKnownHeader() throws {
        let genesisHeaderHex = "0100000000000000000000000000000000000000000000000000000000000000" +
        "000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b" +
        "1e5e4a29ab5f49ffff001d1dac2b7c"
        let headerData = try Data(hexadecimalString: genesisHeaderHex)
        let (header, bytesRead) = try OpalBase.Block.Header.decode(from: headerData)
        
        #expect(bytesRead == headerData.count)
        #expect(header.isProofOfWorkSatisfied)
        
        let invalidHeader = OpalBase.Block.Header(version: header.version,
                                         previousBlockHash: header.previousBlockHash,
                                         merkleRoot: header.merkleRoot,
                                         time: header.time,
                                         bits: header.bits,
                                         nonce: 0)

        #expect(!invalidHeader.isProofOfWorkSatisfied)
    }

    @Test("proof-of-work validation rejects overflowing compact targets")
    func proofOfWorkValidationRejectsOverflowingCompactTargets() {
        let header = OpalBase.Block.Header(
            version: 1,
            previousBlockHash: Data(repeating: 0x11, count: 32),
            merkleRoot: Data(repeating: 0x22, count: 32),
            time: 0,
            bits: 0x23010000,
            nonce: 0
        )

        #expect(!header.isProofOfWorkSatisfied)
    }

    @Test("proof-of-work validation rejects malformed hash field lengths")
    func proofOfWorkValidationRejectsMalformedHashFieldLengths() {
        let header = OpalBase.Block.Header(
            version: 1,
            previousBlockHash: Data(repeating: 0x00, count: 31),
            merkleRoot: Data(repeating: 0x55, count: 32),
            time: 1_700_000_100,
            bits: 0x207fffff,
            nonce: 4
        )

        #expect(!header.isProofOfWorkSatisfied)
    }

}
