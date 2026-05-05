// NetworkFulcrumTransactionConfirmationCountValidator.swift

import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.TransactionClient confirmation count", .tags(.unit))
struct NetworkFulcrumTransactionConfirmationCountValidator {
    @Test("calculates confirmation counts across edge conditions")
    func calculateConfirmationCountHandlesBoundaries() {
        let direct = OpalBase.Network.Fulcrum.TransactionClient.calculateConfirmationCount(
            transactionHeight: 100,
            tipHeight: 100
        )
        #expect(direct == 1)

        let advanced = OpalBase.Network.Fulcrum.TransactionClient.calculateConfirmationCount(
            transactionHeight: 98,
            tipHeight: 102
        )
        #expect(advanced == 5)

        let negativeHeight = OpalBase.Network.Fulcrum.TransactionClient.calculateConfirmationCount(
            transactionHeight: -1,
            tipHeight: 10
        )
        #expect(negativeHeight == nil)

        let zeroHeight = OpalBase.Network.Fulcrum.TransactionClient.calculateConfirmationCount(
            transactionHeight: 0,
            tipHeight: 10
        )
        #expect(zeroHeight == nil)

        let futureTransaction = OpalBase.Network.Fulcrum.TransactionClient.calculateConfirmationCount(
            transactionHeight: 150,
            tipHeight: 140
        )
        #expect(futureTransaction == nil)
    }

    @Test("calculates confirmation counts for edge cases")
    func calculateConfirmationCountEdgeCases() {
        let expectedConfirmations = OpalBase.Network.Fulcrum.TransactionClient.calculateConfirmationCount(
            transactionHeight: 100_000,
            tipHeight: 100_010
        )
        #expect(expectedConfirmations == 11)

        let futureBlock = OpalBase.Network.Fulcrum.TransactionClient.calculateConfirmationCount(
            transactionHeight: 100_011,
            tipHeight: 100_010
        )
        #expect(futureBlock == nil)

        let negativeHeight = OpalBase.Network.Fulcrum.TransactionClient.calculateConfirmationCount(
            transactionHeight: -1,
            tipHeight: 100_010
        )
        #expect(negativeHeight == nil)
    }

    @Test("resolveFee rejects negative fee values instead of treating them as missing")
    func resolveFeeRejectsNegativeValues() throws {
        #expect(try OpalBase.Network.Fulcrum.resolveFee(Optional<Int>.none) == nil)
        #expect(try OpalBase.Network.Fulcrum.resolveFee(Optional(42)) == 42)

        #expect(throws: OpalBase.Network.Error(reason: .decoding, message: "Invalid transaction fee: -1")) {
            _ = try OpalBase.Network.Fulcrum.resolveFee(Optional(-1))
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
}
