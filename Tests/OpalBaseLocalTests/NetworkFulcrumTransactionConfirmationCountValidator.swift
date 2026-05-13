// NetworkFulcrumTransactionConfirmationCountValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.TransactionClient confirmation count", .tags(.unit))
struct NetworkFulcrumTransactionConfirmationCountValidator {
    @Test("calculates confirmation counts across edge conditions")
    func confirmationStatusHandlesBoundaries() throws {
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let direct = try OpalBase.Network.Fulcrum.TransactionClient.makeConfirmationStatus(
            transactionHash: transactionHash,
            transactionHeight: 100,
            tipHeight: 100
        )
        #expect(direct.confirmations == 1)

        let advanced = try OpalBase.Network.Fulcrum.TransactionClient.makeConfirmationStatus(
            transactionHash: transactionHash,
            transactionHeight: 98,
            tipHeight: 102
        )
        #expect(advanced.confirmations == 5)

        let negativeHeight = try OpalBase.Network.Fulcrum.TransactionClient.makeConfirmationStatus(
            transactionHash: transactionHash,
            transactionHeight: -1,
            tipHeight: 10
        )
        #expect(negativeHeight.confirmations == nil)

        let zeroHeight = try OpalBase.Network.Fulcrum.TransactionClient.makeConfirmationStatus(
            transactionHash: transactionHash,
            transactionHeight: 0,
            tipHeight: 10
        )
        #expect(zeroHeight.confirmations == nil)
    }

    @Test("resolveFee rejects negative fee values instead of treating them as missing")
    func resolveFeeRejectsNegativeValues() throws {
        #expect(try OpalBase.Network.Fulcrum.resolveFee(Optional<Int>.none) == nil)
        #expect(try OpalBase.Network.Fulcrum.resolveFee(Optional(42)) == 42)

        #expect(throws: OpalBase.Network.Error(reason: .decoding, message: "Invalid transaction fee: -1")) {
            _ = try OpalBase.Network.Fulcrum.resolveFee(Optional(-1))
        }
    }

    @Test("history mapping rejects malformed transaction identifiers")
    func historyMappingRejectsMalformedTransactionIdentifiers() throws {
        let transactions = [
            HistoryTransactionFixture(transactionIdentifier: "aa", blockHeight: 1, fee: nil)
        ]

        #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: "Invalid history transaction hash length: expected 32 bytes, got 1"
        )) {
            _ = try OpalBase.Network.Fulcrum.mapHistoryTransactions(
                transactions,
                transactionIdentifier: \.transactionIdentifier,
                blockHeight: \.blockHeight,
                fee: \.fee
            )
        }
    }

    @Test("history mapping rejects prefixed transaction identifiers")
    func historyMappingRejectsPrefixedTransactionIdentifiers() throws {
        let transactionIdentifier = "0x" + String(repeating: "a", count: 64)
        let transactions = [
            HistoryTransactionFixture(transactionIdentifier: transactionIdentifier, blockHeight: 1, fee: nil)
        ]

        #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: "Cannot decode history transaction hash: \(transactionIdentifier)"
        )) {
            _ = try OpalBase.Network.Fulcrum.mapHistoryTransactions(
                transactions,
                transactionIdentifier: \.transactionIdentifier,
                blockHeight: \.blockHeight,
                fee: \.fee
            )
        }
    }

    @Test("height resolution rejects malformed wire values instead of clamping")
    func heightResolutionRejectsMalformedWireValues() throws {
        #expect(try OpalBase.Network.Fulcrum.TransactionClient.resolveTransactionHeight(Optional<Int>.none) == nil)
        #expect(try OpalBase.Network.Fulcrum.TransactionClient.resolveTransactionHeight(Optional(-1)) == nil)
        #expect(try OpalBase.Network.Fulcrum.TransactionClient.resolveTransactionHeight(Optional(42)) == 42)
        #expect(try OpalBase.Network.Fulcrum.TransactionClient.resolveTipHeight(42) == 42)

        let oversizedTransactionHeight = UInt64(Int.max) + 1
        #expect(throws: OpalBase.Network.Error(reason: .decoding, message: "Invalid transaction height: \(oversizedTransactionHeight)")) {
            _ = try OpalBase.Network.Fulcrum.TransactionClient.resolveTransactionHeight(Optional(oversizedTransactionHeight))
        }

        #expect(throws: OpalBase.Network.Error(reason: .decoding, message: "Invalid tip height: -1")) {
            _ = try OpalBase.Network.Fulcrum.TransactionClient.resolveTipHeight(-1)
        }
    }

    @Test("confirmation status rejects transaction heights beyond the tip")
    func confirmationStatusRejectsFutureTransactionHeights() throws {
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))

        #expect(throws: OpalBase.Network.Error(
            reason: .protocolViolation,
            message: "Transaction height exceeds tip height: transaction 150, tip 140"
        )) {
            _ = try OpalBase.Network.Fulcrum.TransactionClient.makeConfirmationStatus(
                transactionHash: transactionHash,
                transactionHeight: Optional(150),
                tipHeight: 140
            )
        }
    }

    private struct HistoryTransactionFixture {
        let transactionIdentifier: String
        let blockHeight: Int
        let fee: UInt?
    }
}
