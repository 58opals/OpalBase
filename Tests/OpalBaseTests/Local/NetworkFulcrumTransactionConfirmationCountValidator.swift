// NetworkFulcrumTransactionConfirmationCountValidator.swift

import Testing
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
}
