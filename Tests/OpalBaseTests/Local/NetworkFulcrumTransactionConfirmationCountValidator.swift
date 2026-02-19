import Testing
@testable import OpalBase

@Suite("Network.FulcrumTransactionClient confirmation count", .tags(.unit))
struct NetworkFulcrumTransactionConfirmationCountValidator {
    @Test("calculates confirmation counts across edge conditions")
    func calculateConfirmationCountHandlesBoundaries() {
        let direct = Network.FulcrumTransactionClient.calculateConfirmationCount(
            transactionHeight: 100,
            tipHeight: 100
        )
        #expect(direct == 1)

        let advanced = Network.FulcrumTransactionClient.calculateConfirmationCount(
            transactionHeight: 98,
            tipHeight: 102
        )
        #expect(advanced == 5)

        let negativeHeight = Network.FulcrumTransactionClient.calculateConfirmationCount(
            transactionHeight: -1,
            tipHeight: 10
        )
        #expect(negativeHeight == nil)

        let futureTransaction = Network.FulcrumTransactionClient.calculateConfirmationCount(
            transactionHeight: 150,
            tipHeight: 140
        )
        #expect(futureTransaction == nil)
    }

    @Test("calculates confirmation counts for edge cases")
    func calculateConfirmationCountEdgeCases() {
        let expectedConfirmations = Network.FulcrumTransactionClient.calculateConfirmationCount(
            transactionHeight: 100_000,
            tipHeight: 100_010
        )
        #expect(expectedConfirmations == 11)

        let futureBlock = Network.FulcrumTransactionClient.calculateConfirmationCount(
            transactionHeight: 100_011,
            tipHeight: 100_010
        )
        #expect(futureBlock == nil)

        let negativeHeight = Network.FulcrumTransactionClient.calculateConfirmationCount(
            transactionHeight: -1,
            tipHeight: 100_010
        )
        #expect(negativeHeight == nil)
    }
}
