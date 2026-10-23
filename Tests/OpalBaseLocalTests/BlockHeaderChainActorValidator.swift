// BlockHeaderChainActorValidator.swift

import Foundation
import OpalCrypto
import Testing
import OpalBaseTestSupport
@testable import OpalBase
@testable import OpalBaseCore

@Suite("OpalBase.Block.Header.ChainActor", .tags(.unit, .block))
struct BlockHeaderChainActorValidator {
    @Test("default checkpoint uses the BCH genesis hash")
    func defaultCheckpointUsesBitcoinCashGenesisHash() throws {
        let checkpoint = OpalBase.Block.Header.ChainActor.Checkpoint.defaultCheckpoint
        let expectedHash = try Data(
            hexadecimalString: "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        ).reversedData

        #expect(checkpoint.height == 0)
        #expect(checkpoint.hash == expectedHash)
    }

    @Test("default checkpoint accepts the known genesis header in wire byte order")
    func defaultCheckpointAcceptsKnownGenesisHeader() async throws {
        let headerHex = "0100000000000000000000000000000000000000000000000000000000000000" +
            "000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b" +
            "1e5e4a29ab5f49ffff001d1dac2b7c"
        let bytes = try Data(hexadecimalString: headerHex)
        let (header, bytesRead) = try OpalBase.Block.Header.decode(from: bytes)
        let displayHash = try Data(
            hexadecimalString: "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        )
        let wireHash = try Data(
            hexadecimalString: "6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000"
        )
        try #require(bytesRead == bytes.count)
        try #require(header.isProofOfWorkSatisfied)
        try #require(header.proofOfWorkHash == displayHash)

        let checkpoint = OpalBase.Block.Header.ChainActor.Checkpoint.defaultCheckpoint
        let chain = OpalBase.Block.Header.ChainActor(
            checkpointHeight: checkpoint.height,
            checkpointHash: checkpoint.hash
        )
        let result = try await chain.apply(header: header, at: 0)

        #expect(result.detachedHeights.isEmpty)
        #expect(result.newTip.hash == wireHash)
        #expect(await chain.lookupHeader(at: 0) == header)
    }

    @Test("initial checkpoint normalizes sliced hashes")
    func initialCheckpointNormalizesSlicedHashes() async throws {
        let checkpointHash = Data(repeating: 0x42, count: 32)
        let slicedCheckpointHash = Self.makeSlicedData(from: checkpointHash)

        let checkpoint = OpalBase.Block.Header.ChainActor.Checkpoint(
            height: 7,
            hash: slicedCheckpointHash
        )
        let chain = OpalBase.Block.Header.ChainActor(
            checkpointHeight: 7,
            checkpointHash: slicedCheckpointHash
        )
        let storedHash = try #require(await chain.lookupHash(at: 7))
        let tip = await chain.currentTip

        #expect(slicedCheckpointHash.startIndex != checkpointHash.startIndex)
        #expect(checkpoint.hash == checkpointHash)
        #expect(checkpoint.hash.startIndex == checkpointHash.startIndex)
        #expect(storedHash == checkpointHash)
        #expect(storedHash.startIndex == checkpointHash.startIndex)
        #expect(tip.hash == checkpointHash)
        #expect(tip.hash.startIndex == checkpointHash.startIndex)
    }

    @Test("apply stores headers and remains idempotent for the same block")
    func applyStoresHeadersIdempotently() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 1)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: Self.wireHash(of: checkpointHeader))

        let firstResult = try await chain.apply(header: checkpointHeader, at: 0)
        let secondResult = try await chain.apply(header: checkpointHeader, at: 0)

        #expect(firstResult.detachedHeights.isEmpty)
        #expect(secondResult.detachedHeights.isEmpty)
        #expect(await chain.currentTip == .init(height: 0, hash: Self.wireHash(of: checkpointHeader)))
        #expect(await chain.lookupHash(at: 0) == Self.wireHash(of: checkpointHeader))
        #expect(await chain.lookupHeader(at: 0) == checkpointHeader)
    }

    @Test("apply rejects invalid proof of work")
    func applyRejectsInvalidProofOfWork() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 2)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: Self.wireHash(of: checkpointHeader))
        let invalidHeader = OpalBase.Block.Header(
            version: 1,
            previousBlockHash: Self.wireHash(of: checkpointHeader),
            merkleRoot: Data(repeating: 0x55, count: 32),
            time: 1_700_000_100,
            bits: 0x1d00ffff,
            nonce: 0
        )

        await #expect(throws: OpalBase.Block.Header.ChainActor.Error.invalidProofOfWork(height: 1)) {
            _ = try await chain.apply(header: invalidHeader, at: 1)
        }
    }

    @Test("apply rejects non-connecting headers")
    func applyRejectsNonConnectingHeaders() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 3)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: Self.wireHash(of: checkpointHeader))
        _ = try await chain.apply(header: checkpointHeader, at: 0)

        let nextHeader = try Self.makeSatisfiedHeader(previousBlockHash: Self.wireHash(of: checkpointHeader), seed: 4)
        _ = try await chain.apply(header: nextHeader, at: 1)

        let disconnectedHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x99, count: 32), seed: 5)
        await #expect(throws: OpalBase.Block.Header.ChainActor.Error.doesNotConnect(height: 2)) {
            _ = try await chain.apply(header: disconnectedHeader, at: 2)
        }
    }

    @Test("apply emits resynchronization for a competing header at the tip")
    func applyEmitsResynchronizationForCompetingHeaders() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 6)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: Self.wireHash(of: checkpointHeader))
        _ = try await chain.apply(header: checkpointHeader, at: 0)

        let primaryHeader = try Self.makeSatisfiedHeader(previousBlockHash: Self.wireHash(of: checkpointHeader), seed: 7)
        _ = try await chain.apply(header: primaryHeader, at: 1)

        let competingHeader = try Self.makeSatisfiedHeader(previousBlockHash: Self.wireHash(of: checkpointHeader), seed: 8)
        let result = try await chain.apply(header: competingHeader, at: 1)
        let events = await chain.dequeueMaintenanceEvents()

        #expect(result.detachedHeights == [1])
        #expect(await chain.currentTip == .init(height: 1, hash: Self.wireHash(of: competingHeader)))
        #expect(events == [.requiresResynchronization(from: .init(height: 1, hash: Self.wireHash(of: competingHeader)))])
    }

    @Test("apply rejects disconnected competing headers without detaching current tip")
    func applyRejectsDisconnectedCompetingHeadersWithoutDetachingCurrentTip() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 20)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: Self.wireHash(of: checkpointHeader))
        _ = try await chain.apply(header: checkpointHeader, at: 0)

        let firstHeader = try Self.makeSatisfiedHeader(previousBlockHash: Self.wireHash(of: checkpointHeader), seed: 21)
        _ = try await chain.apply(header: firstHeader, at: 1)
        let secondHeader = try Self.makeSatisfiedHeader(previousBlockHash: Self.wireHash(of: firstHeader), seed: 22)
        _ = try await chain.apply(header: secondHeader, at: 2)

        let disconnectedCompetingHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x99, count: 32), seed: 23)
        await #expect(throws: OpalBase.Block.Header.ChainActor.Error.doesNotConnect(height: 2)) {
            _ = try await chain.apply(header: disconnectedCompetingHeader, at: 2)
        }

        #expect(await chain.currentTip == .init(height: 2, hash: Self.wireHash(of: secondHeader)))
        #expect(await chain.lookupHeader(at: 2) == secondHeader)
        #expect(await chain.dequeueMaintenanceEvents().isEmpty)
    }

    @Test("apply rejects headers below a nonzero checkpoint")
    func applyRejectsHeadersBelowNonzeroCheckpoint() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 24)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 10, checkpointHash: Self.wireHash(of: checkpointHeader))

        let earlierHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x99, count: 32), seed: 25)
        await #expect(
            throws: OpalBase.Block.Header.ChainActor.Error.checkpointViolation(
                expected: .init(height: 10, hash: Self.wireHash(of: checkpointHeader)),
                actual: .init(height: 9, hash: Self.wireHash(of: earlierHeader))
            )
        ) {
            _ = try await chain.apply(header: earlierHeader, at: 9)
        }

        #expect(await chain.currentTip == .init(height: 10, hash: Self.wireHash(of: checkpointHeader)))
        #expect(await chain.lookupHeader(at: 9) == nil)
        #expect(await chain.lookupHash(at: 9) == nil)
    }

    @Test("apply queues resynchronization without accepting a gap header")
    func applyQueuesResynchronizationWithoutAcceptingGapHeader() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 30)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: Self.wireHash(of: checkpointHeader))
        _ = try await chain.apply(header: checkpointHeader, at: 0)

        let gapHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x88, count: 32), seed: 31)
        let result = try await chain.apply(header: gapHeader, at: 3)
        let events = await chain.dequeueMaintenanceEvents()

        #expect(result.detachedHeights.isEmpty)
        #expect(result.newTip == .init(height: 0, hash: Self.wireHash(of: checkpointHeader)))
        #expect(await chain.currentTip == .init(height: 0, hash: Self.wireHash(of: checkpointHeader)))
        #expect(await chain.lookupHeader(at: 0) == checkpointHeader)
        #expect(await chain.lookupHeader(at: 3) == nil)
        #expect(events == [.requiresResynchronization(from: .init(height: 3, hash: Self.wireHash(of: gapHeader)))])
    }

    @Test("updateTipStatus publishes a stale-tip event only once per status")
    func updateTipStatusPublishesStaleTipOncePerStatus() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 9, time: 1_700_000_000)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: Self.wireHash(of: checkpointHeader))
        _ = try await chain.apply(header: checkpointHeader, at: 0)

        let now = Date(timeIntervalSince1970: 1_700_000_000 + (3 * 60 * 60))
        let later = Date(timeIntervalSince1970: 1_700_000_000 + (4 * 60 * 60))
        await chain.updateTipStatus(now: now, staleInterval: 60 * 60)
        let firstEvents = await chain.dequeueMaintenanceEvents()

        await chain.updateTipStatus(now: later, staleInterval: 60 * 60)
        let secondEvents = await chain.dequeueMaintenanceEvents()

        #expect(firstEvents.count == 1)
        #expect(secondEvents.isEmpty)
    }
}

private extension BlockHeaderChainActorValidator {
    static func wireHash(of header: OpalBase.Block.Header) -> Data {
        OpalCrypto.Hashing.hash256(header.encode())
    }

    static func makeSlicedData(from data: Data) -> Data {
        let paddedData = Data([0x00]) + data
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
    }

    static func makeSatisfiedHeader(
        previousBlockHash: Data,
        seed: UInt8,
        time: UInt32 = 1_700_000_000
    ) throws -> OpalBase.Block.Header {
        var nonce: UInt32 = 0
        let merkleRoot = Data(repeating: seed, count: 32)
        while nonce < UInt32.max {
            let header = OpalBase.Block.Header(
                version: 1,
                previousBlockHash: previousBlockHash,
                merkleRoot: merkleRoot,
                time: time + UInt32(seed),
                bits: 0x207fffff,
                nonce: nonce
            )
            if header.isProofOfWorkSatisfied {
                return header
            }
            nonce &+= 1
        }

        throw OpalBase.Block.Header.ChainActor.Error.invalidProofOfWork(height: 0)
    }
}
