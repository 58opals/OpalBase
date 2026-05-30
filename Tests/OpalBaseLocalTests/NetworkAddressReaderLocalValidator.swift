// NetworkAddressReaderLocalValidator.swift

import Foundation
import SwiftFulcrum
import Testing
@testable import OpalBase

@Suite("OpalBase.Network.AddressReader", .tags(.unit, .network))
struct NetworkAddressReaderLocalValidator {
    @Test("preserves negative unconfirmed balances from the underlying network client")
    func preservesNegativeUnconfirmedBalances() async throws {
        let expectedBalance = OpalBase.Network.AddressBalance(confirmed: 1_200, unconfirmed: -300)
        let reader = OpalBase.Network.AddressReader(
            fetchBalance: { _, _ in expectedBalance },
            fetchUnspentOutputs: { _, _ in .init() },
            fetchHistory: { _, _ in .init() },
            fetchFirstUse: { _ in nil },
            fetchMempoolTransactions: { _ in .init() },
            fetchScriptHash: { _ in "" },
            subscribeToAddress: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )

        let balance = try await reader.fetchBalance(
            for: "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a",
            tokenFilter: .include
        )

        #expect(balance == expectedBalance)
        #expect(balance.unconfirmed == -300)
    }
    
    @Test("first-use results require valid block and transaction hashes")
    func firstUseResultsRequireValidHashes() throws {
        let blockHash = String(repeating: "a", count: 64)
        let transactionIdentifier = String(repeating: "b", count: 64)
        
        let firstUse = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
            blockHeight: 1,
            blockHash: blockHash,
            transactionIdentifier: transactionIdentifier
        )
        
        #expect(firstUse.blockHeight == 1)
        #expect(firstUse.blockHash == blockHash)
        #expect(firstUse.transactionIdentifier == transactionIdentifier)
        
        let blockHashFailure = Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
                blockHeight: 1,
                blockHash: "aa",
                transactionIdentifier: transactionIdentifier
            )
        }
        #expect(blockHashFailure.reason == .decoding)
        #expect(blockHashFailure.message == "Invalid first-use block hash length: expected 32 bytes, got 1")
        
        let prefixedBlockHashFailure = Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
                blockHeight: 1,
                blockHash: "0x\(blockHash)",
                transactionIdentifier: transactionIdentifier
            )
        }
        #expect(prefixedBlockHashFailure.reason == .decoding)
        #expect(prefixedBlockHashFailure.message == "Cannot decode first-use block hash: 0x\(blockHash)")
        
        let transactionHashFailure = Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
                blockHeight: 1,
                blockHash: blockHash,
                transactionIdentifier: "bb"
            )
        }
        #expect(transactionHashFailure.reason == .decoding)
        #expect(transactionHashFailure.message == "Invalid first-use transaction hash length: expected 32 bytes, got 1")
    }

    @Test("first-use results reject partial responses")
    func firstUseResultsRejectPartialResponses() throws {
        let unused = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
            blockHeight: nil,
            blockHash: nil,
            transactionIdentifier: nil
        )
        #expect(unused == nil)
        
        let failure = Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
                blockHeight: 1,
                blockHash: nil,
                transactionIdentifier: String(repeating: "b", count: 64)
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Incomplete first-use response")
    }
    
    @Test("script hash results require valid hashes")
    func scriptHashResultsRequireValidHashes() throws {
        let scriptHash = String(repeating: "c", count: 64)
        
        #expect(try OpalBase.Network.Fulcrum.AddressReader.validateScriptHash(scriptHash) == scriptHash)
        
        let failure = Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.validateScriptHash("cc")
        }
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid script hash length: expected 32 bytes, got 1")
        
        let prefixedFailure = Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.validateScriptHash("0x\(scriptHash)")
        }
        #expect(prefixedFailure.reason == .decoding)
        #expect(prefixedFailure.message == "Cannot decode script hash: 0x\(scriptHash)")
    }

    @Test("script hash results must match the requested address")
    func scriptHashResultsMustMatchRequestedAddress() throws {
        let address = try OpalBase.Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let mismatchedScriptHash = String(repeating: "c", count: 64)

        let failure = Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.validateScriptHash(
                mismatchedScriptHash,
                matches: address
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Address script hash mismatch")
    }

    @Test("address balance conversion rejects confirmed values above maximum supply")
    func rejectConfirmedValuesAboveMaximumSupplyDuringAddressBalanceConversion() throws {
        #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: "Confirmed balance exceeds maximum supply"
        )) {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeAddressBalance(
                confirmed: OpalBase.Satoshi.maximumSatoshi + 1,
                unconfirmed: 0
            )
        }
    }

    @Test("address balance conversion accepts valid confirmed value boundaries")
    func acceptValidConfirmedValueBoundariesDuringAddressBalanceConversion() throws {
        let balance = try OpalBase.Network.Fulcrum.AddressReader.makeAddressBalance(
            confirmed: OpalBase.Satoshi.maximumSatoshi,
            unconfirmed: -1
        )

        #expect(balance.confirmed == OpalBase.Satoshi.maximumSatoshi)
        #expect(balance.unconfirmed == -1)
    }

    @Test("unspent output conversion rejects values above maximum supply")
    func rejectValuesAboveMaximumSupplyDuringUnspentOutputConversion() throws {
        let item = try Self.makeAddressListUnspentItem(
            value: OpalBase.Satoshi.maximumSatoshi + 1
        )

        #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: "Unspent output value exceeds maximum supply"
        )) {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeUnspentOutput(
                from: item,
                lockingScriptData: Data([0x51])
            )
        }
    }
    
    private static func captureNetworkError(_ work: () throws -> Void) -> OpalBase.Network.Error {
        do {
            try work()
            Issue.record("Expected OpalBase.Network.Error")
            return .init(reason: .unknown)
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch {
            Issue.record("Unexpected error: \(error)")
            return .init(reason: .unknown, message: String(describing: error))
        }
    }

    private static func makeAddressListUnspentItem(
        value: UInt64
    ) throws -> SwiftFulcrum.Response.Blockchain.Address.ListUnspent.Item {
        let transactionHash = String(repeating: "1", count: 64)
        let payload = Data(
            """
            [{"height":1,"tx_hash":"\(transactionHash)","tx_pos":0,"value":\(value)}]
            """.utf8
        )
        let result = try JSONDecoder().decode(
            SwiftFulcrum.Response.Blockchain.Address.ListUnspent.self,
            from: payload
        )
        return try #require(result.items.first)
    }
}
