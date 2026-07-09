// NetworkFulcrumTransactionConfirmationCountValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.TransactionClient confirmation count", .tags(.unit))
struct NetworkFulcrumTransactionConfirmationCountValidator {
    @Test(
        "calculates confirmation counts for confirmed heights",
        arguments: confirmationCountCases
    )
    func confirmationStatusCalculatesConfirmedCounts(_ confirmationCase: ConfirmationCountCase) throws {
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let status = try OpalBase.Network.Fulcrum.TransactionClient.makeConfirmationStatus(
            transactionHash: transactionHash,
            transactionHeight: confirmationCase.transactionHeight,
            tipHeight: confirmationCase.tipHeight
        )

        #expect(status.confirmations == confirmationCase.expectedConfirmations)
    }

    @Test(
        "leaves unconfirmed sentinel heights without confirmation counts",
        arguments: [-1, 0]
    )
    func confirmationStatusLeavesUnconfirmedSentinelHeightsWithoutCounts(_ transactionHeight: Int) throws {
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let status = try OpalBase.Network.Fulcrum.TransactionClient.makeConfirmationStatus(
            transactionHash: transactionHash,
            transactionHeight: transactionHeight,
            tipHeight: 10
        )

        #expect(status.confirmations == nil)
    }

    @Test("resolveFee preserves missing and valid fee values")
    func preserveValidFeeValuesDuringFeeResolution() throws {
        #expect(try OpalBase.Network.Fulcrum.resolveFee(Optional<Int>.none) == nil)
        #expect(try OpalBase.Network.Fulcrum.resolveFee(Optional(42)) == 42)
    }

    @Test(
        "resolveFee rejects invalid fee values instead of treating them as missing",
        arguments: [
            Int64(-1),
            Int64(OpalBase.Satoshi.maximumSatoshi + 1)
        ]
    )
    func rejectInvalidFeeValuesDuringFeeResolution(_ invalidFee: Int64) throws {
        #expect(throws: OpalBase.Network.Error(reason: .decoding, message: "Invalid transaction fee: \(invalidFee)")) {
            _ = try OpalBase.Network.Fulcrum.resolveFee(Optional(invalidFee))
        }
    }

    @Test("history mapping rejects invalid transaction identifiers", arguments: invalidHistoryTransactionIdentifierCases)
    fileprivate func historyMappingRejectsInvalidTransactionIdentifiers(_ invalidCase: InvalidHistoryTransactionIdentifierCase) throws {
        let transactions = [
            HistoryTransactionFixture(transactionIdentifier: invalidCase.transactionIdentifier, blockHeight: 1, fee: nil)
        ]

        #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: invalidCase.expectedMessage
        )) {
            _ = try OpalBase.Network.Fulcrum.mapHistoryTransactions(
                transactions,
                transactionIdentifier: \.transactionIdentifier,
                blockHeight: \.blockHeight,
                fee: \.fee
            )
        }
    }

    @Test("history mapping rejects heights below unconfirmed sentinel")
    func historyMappingRejectsHeightsBelowUnconfirmedSentinel() throws {
        let transactions = [
            HistoryTransactionFixture(
                transactionIdentifier: String(repeating: "a", count: 64),
                blockHeight: -2,
                fee: nil
            )
        ]

        #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: "Invalid history transaction height: -2"
        )) {
            _ = try OpalBase.Network.Fulcrum.mapHistoryTransactions(
                transactions,
                transactionIdentifier: \.transactionIdentifier,
                blockHeight: \.blockHeight,
                fee: \.fee
            )
        }
    }

    @Test("history mapping normalizes uppercase transaction identifiers")
    func historyMappingNormalizesUppercaseTransactionIdentifiers() throws {
        let transactionIdentifier = String(repeating: "a", count: 64)
        let transactions = [
            HistoryTransactionFixture(
                transactionIdentifier: transactionIdentifier.uppercased(),
                blockHeight: 1,
                fee: nil
            )
        ]

        let entries = try OpalBase.Network.Fulcrum.mapHistoryTransactions(
            transactions,
            transactionIdentifier: \.transactionIdentifier,
            blockHeight: \.blockHeight,
            fee: \.fee
        )

        let entry = try #require(entries.first)
        #expect(entry.transactionIdentifier == transactionIdentifier)
    }

    @Test("mempool mapping rejects confirmed transaction heights")
    func mempoolMappingRejectsConfirmedTransactionHeights() throws {
        let transactions = [
            HistoryTransactionFixture(
                transactionIdentifier: String(repeating: "a", count: 64),
                blockHeight: 1,
                fee: nil
            )
        ]

        #expect(throws: OpalBase.Network.Error(
            reason: .protocolViolation,
            message: "Mempool response included a confirmed transaction"
        )) {
            _ = try OpalBase.Network.Fulcrum.mapMempoolTransactions(
                transactions,
                transactionIdentifier: \.transactionIdentifier,
                blockHeight: \.blockHeight,
                fee: \.fee
            )
        }
    }

    @Test(
        "mempool mapping accepts unconfirmed transaction heights",
        arguments: [-1, 0]
    )
    func mempoolMappingAcceptsUnconfirmedTransactionHeights(_ blockHeight: Int) throws {
        let transactions = [
            HistoryTransactionFixture(
                transactionIdentifier: String(repeating: "a", count: 64),
                blockHeight: blockHeight,
                fee: nil
            )
        ]

        let entries = try OpalBase.Network.Fulcrum.mapMempoolTransactions(
            transactions,
            transactionIdentifier: \.transactionIdentifier,
            blockHeight: \.blockHeight,
            fee: \.fee
        )

        let entry = try #require(entries.first)
        #expect(entry.blockHeight == blockHeight)
    }

    @Test("height resolution preserves missing, unconfirmed, and valid wire values")
    func heightResolutionPreservesMissingUnconfirmedAndValidWireValues() throws {
        #expect(try OpalBase.Network.Fulcrum.TransactionClient.resolveTransactionHeight(Optional<Int>.none) == nil)
        #expect(try OpalBase.Network.Fulcrum.TransactionClient.resolveTransactionHeight(Optional(-1)) == nil)
        #expect(try OpalBase.Network.Fulcrum.TransactionClient.resolveTransactionHeight(Optional(42)) == 42)
        #expect(try OpalBase.Network.Fulcrum.TransactionClient.resolveTipHeight(42) == 42)
    }

    @Test("height resolution rejects transaction heights below the unconfirmed sentinel")
    func heightResolutionRejectsTransactionHeightsBelowUnconfirmedSentinel() throws {
        #expect(throws: OpalBase.Network.Error(reason: .decoding, message: "Invalid transaction height: -2")) {
            _ = try OpalBase.Network.Fulcrum.TransactionClient.resolveTransactionHeight(Optional(-2))
        }
    }

    @Test("height resolution rejects oversized transaction heights")
    func heightResolutionRejectsOversizedTransactionHeights() throws {
        let oversizedTransactionHeight = UInt64(Int.max) + 1
        #expect(throws: OpalBase.Network.Error(reason: .decoding, message: "Invalid transaction height: \(oversizedTransactionHeight)")) {
            _ = try OpalBase.Network.Fulcrum.TransactionClient.resolveTransactionHeight(Optional(oversizedTransactionHeight))
        }
    }

    @Test("tip height resolution rejects negative wire values")
    func tipHeightResolutionRejectsNegativeWireValues() throws {
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

    @Test("confirmation status validation rejects non-positive present heights", arguments: [-1, 0])
    func confirmationStatusValidationRejectsNonPositivePresentHeights(height: Int) throws {
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x22, count: 32))

        let status = OpalBase.Network.TransactionConfirmationStatus(
            transactionHash: transactionHash,
            transactionHeight: height,
            tipHeight: 100,
            confirmations: nil
        )

        #expect(throws: OpalBase.Network.Error(
            reason: .protocolViolation,
            message: "Confirmation status height must be positive"
        )) {
            try status.validateConsistency()
        }
    }

    private struct HistoryTransactionFixture {
        let transactionIdentifier: String
        let blockHeight: Int
        let fee: UInt?
    }

    private static let confirmationCountCases = [
        ConfirmationCountCase(
            transactionHeight: 100,
            tipHeight: 100,
            expectedConfirmations: 1
        ),
        ConfirmationCountCase(
            transactionHeight: 98,
            tipHeight: 102,
            expectedConfirmations: 5
        )
    ]

    private static let invalidHistoryTransactionIdentifierCases = [
        InvalidHistoryTransactionIdentifierCase(
            description: "short hex",
            transactionIdentifier: "aa",
            expectedMessage: "Invalid history transaction hash length: expected 32 bytes, got 1"
        ),
        InvalidHistoryTransactionIdentifierCase(
            description: "oversized hex",
            transactionIdentifier: String(repeating: "a", count: 4_096),
            expectedMessage: "Invalid history transaction hash length: expected 32 bytes, got 2048"
        ),
        InvalidHistoryTransactionIdentifierCase(
            description: "prefixed hex",
            transactionIdentifier: "0x" + String(repeating: "a", count: 64),
            expectedMessage: "Cannot decode history transaction hash: 0x\(String(repeating: "a", count: 64))"
        )
    ]

    struct ConfirmationCountCase: Sendable {
        let transactionHeight: Int
        let tipHeight: Int
        let expectedConfirmations: UInt
    }

    struct InvalidHistoryTransactionIdentifierCase: CustomStringConvertible, Sendable {
        let description: String
        let transactionIdentifier: String
        let expectedMessage: String
    }
}
