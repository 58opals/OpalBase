// NetworkAddressReaderLocalValidator.swift

import Foundation
import SwiftFulcrum
import Testing
@testable import OpalBase

@Suite("OpalBase.Network.AddressReader", .tags(.unit, .network))
struct NetworkAddressReaderLocalValidator {
    private static let firstUseBlockHash = String(repeating: "a", count: 64)
    private static let firstUseTransactionIdentifier = String(repeating: "b", count: 64)

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
        let firstUse = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
            blockHeight: 1,
            blockHash: Self.firstUseBlockHash,
            transactionIdentifier: Self.firstUseTransactionIdentifier
        )
        
        #expect(firstUse.blockHeight == 1)
        #expect(firstUse.blockHash == Self.firstUseBlockHash)
        #expect(firstUse.transactionIdentifier == Self.firstUseTransactionIdentifier)
        
        let blockHashFailure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
                blockHeight: 1,
                blockHash: "aa",
                transactionIdentifier: Self.firstUseTransactionIdentifier
            )
        }
        #expect(blockHashFailure.reason == .decoding)
        #expect(blockHashFailure.message == "Invalid first-use block hash length: expected 32 bytes, got 1")
        
        let prefixedBlockHashFailure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
                blockHeight: 1,
                blockHash: "0x\(Self.firstUseBlockHash)",
                transactionIdentifier: Self.firstUseTransactionIdentifier
            )
        }
        #expect(prefixedBlockHashFailure.reason == .decoding)
        #expect(prefixedBlockHashFailure.message == "Cannot decode first-use block hash: 0x\(Self.firstUseBlockHash)")
        
        let transactionHashFailure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
                blockHeight: 1,
                blockHash: Self.firstUseBlockHash,
                transactionIdentifier: "bb"
            )
        }
        #expect(transactionHashFailure.reason == .decoding)
        #expect(transactionHashFailure.message == "Invalid first-use transaction hash length: expected 32 bytes, got 1")
    }

    @Test("first-use results reject zero confirmed heights")
    func firstUseResultsRejectZeroConfirmedHeights() throws {
        let failure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
                blockHeight: 0,
                blockHash: Self.firstUseBlockHash,
                transactionIdentifier: Self.firstUseTransactionIdentifier
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "First-use block height must be positive")
    }

    @Test("first-use optional response rejects zero confirmed heights")
    func firstUseOptionalResponseRejectsZeroConfirmedHeights() throws {
        let failure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
                blockHeight: Optional<UInt>(0),
                blockHash: Self.firstUseBlockHash,
                transactionIdentifier: Self.firstUseTransactionIdentifier
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "First-use block height must be positive")
    }

    @Test("first-use results reject partial responses")
    func firstUseResultsRejectPartialResponses() throws {
        let unused = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
            blockHeight: nil,
            blockHash: nil,
            transactionIdentifier: nil
        )
        #expect(unused == nil)
        
        let failure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeFirstUse(
                blockHeight: 1,
                blockHash: nil,
                transactionIdentifier: Self.firstUseTransactionIdentifier
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Incomplete first-use response")
    }

    @Test("address history mapping accepts confirmed transactions")
    func addressHistoryMappingAcceptsConfirmedTransactions() throws {
        let transactions = [
            AddressTransactionFixture(
                transactionIdentifier: String(repeating: "a", count: 64),
                blockHeight: 1,
                fee: nil
            )
        ]

        let entries = try OpalBase.Network.Fulcrum.AddressReader.mapAddressHistoryTransactions(
            transactions,
            transactionIdentifier: \.transactionIdentifier,
            blockHeight: \.blockHeight,
            fee: \.fee
        )

        let entry = try #require(entries.first)
        #expect(entry.blockHeight == 1)
    }

    @Test("address mempool mapping rejects confirmed transactions")
    func addressMempoolMappingRejectsConfirmedTransactions() throws {
        let transactions = [
            AddressTransactionFixture(
                transactionIdentifier: String(repeating: "b", count: 64),
                blockHeight: 1,
                fee: nil
            )
        ]

        #expect(throws: OpalBase.Network.Error(
            reason: .protocolViolation,
            message: "Mempool response included a confirmed transaction"
        )) {
            _ = try OpalBase.Network.Fulcrum.AddressReader.mapAddressMempoolTransactions(
                transactions,
                transactionIdentifier: \.transactionIdentifier,
                blockHeight: \.blockHeight,
                fee: \.fee
            )
        }
    }

    @Test(
        "address mempool mapping accepts unconfirmed transaction heights",
        arguments: [-1, 0]
    )
    func addressMempoolMappingAcceptsUnconfirmedTransactionHeights(_ blockHeight: Int) throws {
        let transactions = [
            AddressTransactionFixture(
                transactionIdentifier: String(repeating: "c", count: 64),
                blockHeight: blockHeight,
                fee: nil
            )
        ]

        let entries = try OpalBase.Network.Fulcrum.AddressReader.mapAddressMempoolTransactions(
            transactions,
            transactionIdentifier: \.transactionIdentifier,
            blockHeight: \.blockHeight,
            fee: \.fee
        )

        let entry = try #require(entries.first)
        #expect(entry.blockHeight == blockHeight)
    }
    
    @Test("script hash results require valid hashes")
    func scriptHashResultsRequireValidHashes() throws {
        let scriptHash = String(repeating: "c", count: 64)
        
        #expect(try OpalBase.Network.Fulcrum.AddressReader.validateScriptHash(scriptHash) == scriptHash)
        
        let failure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.validateScriptHash("cc")
        }
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid script hash length: expected 32 bytes, got 1")
        
        let prefixedFailure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.AddressReader.validateScriptHash("0x\(scriptHash)")
        }
        #expect(prefixedFailure.reason == .decoding)
        #expect(prefixedFailure.message == "Cannot decode script hash: 0x\(scriptHash)")
    }

    @Test("script hash results must match the requested address")
    func scriptHashResultsMustMatchRequestedAddress() throws {
        let address = try OpalBase.Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let mismatchedScriptHash = String(repeating: "c", count: 64)

        let failure = try Self.captureNetworkError {
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

    @Test("address balance conversion rejects unconfirmed magnitudes above maximum supply")
    func rejectUnconfirmedMagnitudesAboveMaximumSupplyDuringAddressBalanceConversion() throws {
        let maximumSignedSatoshi = Int64(OpalBase.Satoshi.maximumSatoshi)

        #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: "Unconfirmed balance exceeds maximum supply"
        )) {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeAddressBalance(
                confirmed: 0,
                unconfirmed: maximumSignedSatoshi + 1
            )
        }

        #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: "Unconfirmed balance exceeds maximum supply"
        )) {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeAddressBalance(
                confirmed: 0,
                unconfirmed: -maximumSignedSatoshi - 1
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

    @Test("address balance conversion rejects aggregate values above maximum supply")
    func rejectAggregateValuesAboveMaximumSupplyDuringAddressBalanceConversion() throws {
        #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: "Address balance exceeds maximum supply"
        )) {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeAddressBalance(
                confirmed: OpalBase.Satoshi.maximumSatoshi,
                unconfirmed: 1
            )
        }
    }

    @Test("address balance conversion rejects negative aggregate values")
    func rejectNegativeAggregateValuesDuringAddressBalanceConversion() throws {
        #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: "Address balance cannot be negative"
        )) {
            _ = try OpalBase.Network.Fulcrum.AddressReader.makeAddressBalance(
                confirmed: 0,
                unconfirmed: -1
            )
        }
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
    
    private enum NetworkErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    private static func captureNetworkError(_ work: () throws -> Void) throws -> OpalBase.Network.Error {
        do {
            try work()
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch {
            throw NetworkErrorCaptureFailure.unexpected(error)
        }
        throw NetworkErrorCaptureFailure.didNotThrow
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

    private struct AddressTransactionFixture {
        let transactionIdentifier: String
        let blockHeight: Int
        let fee: UInt?
    }
}
