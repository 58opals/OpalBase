// BlockHeaderChainActorValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Block.Header.ChainActor", .tags(.unit, .block))
struct BlockHeaderChainActorValidator {
    @Test("apply stores headers and remains idempotent for the same block")
    func applyStoresHeadersIdempotently() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 1)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: checkpointHeader.proofOfWorkHash)

        let firstResult = try await chain.apply(header: checkpointHeader, at: 0)
        let secondResult = try await chain.apply(header: checkpointHeader, at: 0)

        #expect(firstResult.detachedHeights.isEmpty)
        #expect(secondResult.detachedHeights.isEmpty)
        #expect(await chain.currentTip == .init(height: 0, hash: checkpointHeader.proofOfWorkHash))
        #expect(await chain.lookupHash(at: 0) == checkpointHeader.proofOfWorkHash)
        #expect(await chain.lookupHeader(at: 0) == checkpointHeader)
    }

    @Test("apply rejects invalid proof of work")
    func applyRejectsInvalidProofOfWork() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 2)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: checkpointHeader.proofOfWorkHash)
        let invalidHeader = OpalBase.Block.Header(
            version: 1,
            previousBlockHash: checkpointHeader.proofOfWorkHash,
            merkleRoot: Data(repeating: 0x55, count: 32),
            time: 1_700_000_100,
            bits: 0x1d00ffff,
            nonce: 0
        )

        do {
            _ = try await chain.apply(header: invalidHeader, at: 1)
            Issue.record("Expected invalid proof-of-work failure")
        } catch let error as OpalBase.Block.Header.ChainActor.Error {
            guard case .invalidProofOfWork(let height) = error else {
                Issue.record("Expected invalidProofOfWork, got: \(error)")
                return
            }
            #expect(height == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("apply rejects non-connecting headers")
    func applyRejectsNonConnectingHeaders() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 3)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: checkpointHeader.proofOfWorkHash)
        _ = try await chain.apply(header: checkpointHeader, at: 0)

        let nextHeader = try Self.makeSatisfiedHeader(previousBlockHash: checkpointHeader.proofOfWorkHash, seed: 4)
        _ = try await chain.apply(header: nextHeader, at: 1)

        let disconnectedHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x99, count: 32), seed: 5)
        do {
            _ = try await chain.apply(header: disconnectedHeader, at: 2)
            Issue.record("Expected does-not-connect failure")
        } catch let error as OpalBase.Block.Header.ChainActor.Error {
            guard case .doesNotConnect(let height) = error else {
                Issue.record("Expected doesNotConnect, got: \(error)")
                return
            }
            #expect(height == 2)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("apply emits resynchronization for a competing header at the tip")
    func applyEmitsResynchronizationForCompetingHeaders() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 6)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: checkpointHeader.proofOfWorkHash)
        _ = try await chain.apply(header: checkpointHeader, at: 0)

        let primaryHeader = try Self.makeSatisfiedHeader(previousBlockHash: checkpointHeader.proofOfWorkHash, seed: 7)
        _ = try await chain.apply(header: primaryHeader, at: 1)

        let competingHeader = try Self.makeSatisfiedHeader(previousBlockHash: checkpointHeader.proofOfWorkHash, seed: 8)
        let result = try await chain.apply(header: competingHeader, at: 1)
        let events = await chain.dequeueMaintenanceEvents()

        #expect(result.detachedHeights == [1])
        #expect(await chain.currentTip == .init(height: 1, hash: competingHeader.proofOfWorkHash))
        #expect(events == [.requiresResynchronization(from: .init(height: 1, hash: competingHeader.proofOfWorkHash))])
    }

    @Test("updateTipStatus publishes a stale-tip event only once per status")
    func updateTipStatusPublishesStaleTipOncePerStatus() async throws {
        let checkpointHeader = try Self.makeSatisfiedHeader(previousBlockHash: Data(repeating: 0x00, count: 32), seed: 9, time: 1_700_000_000)
        let chain = OpalBase.Block.Header.ChainActor(checkpointHeight: 0, checkpointHash: checkpointHeader.proofOfWorkHash)
        _ = try await chain.apply(header: checkpointHeader, at: 0)

        let now = Date(timeIntervalSince1970: 1_700_000_000 + (3 * 60 * 60))
        await chain.updateTipStatus(now: now, staleInterval: 60 * 60)
        let firstEvents = await chain.dequeueMaintenanceEvents()

        await chain.updateTipStatus(now: now, staleInterval: 60 * 60)
        let secondEvents = await chain.dequeueMaintenanceEvents()

        #expect(firstEvents.count == 1)
        #expect(secondEvents.isEmpty)
    }
}

private extension BlockHeaderChainActorValidator {
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
