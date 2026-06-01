// AddressBookCoinSelectorValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Address.Book Coin Selector", .tags(.unit, .address))
struct AddressBookCoinSelectorValidator {
    @Test("select throws when utxo accumulation overflows UInt64")
    func selectGreedyThrowsOnOverflow() async throws {
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let utxoWithMaximumValue = OpalBase.Transaction.Output.Unspent(
            value: UInt64.max - 1,
            lockingScript: Data(),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        let utxoTriggeringOverflow = OpalBase.Transaction.Output.Unspent(
            value: 10,
            lockingScript: Data(),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )

        let configuration = OpalBase.Address.Book.CoinSelection.Configuration.makeTemplateConfiguration(strategy: .greedyLargestFirst)
        let coinSelector = OpalBase.Address.Book.CoinSelector(
            utxos: [utxoWithMaximumValue, utxoTriggeringOverflow],
            configuration: configuration,
            targetAmount: UInt64.max,
            feePerByte: 0,
            minimumRelayFeeRate: 0
        )

        #expect(throws: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try coinSelector.select()
        }
    }

    @Test("select sweep all throws when all utxos cannot satisfy target")
    func selectSweepAllThrowsWhenSelectionCannotSatisfyTarget() throws {
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let unspent = OpalBase.Transaction.Output.Unspent(
            value: 500,
            lockingScript: Data([0x51]),
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        let recipientOutputs = [OpalBase.Transaction.Output(value: 1_000, lockingScript: Data([0x51]))]
        let configuration = OpalBase.Address.Book.CoinSelection.Configuration(
            recipientOutputs: recipientOutputs,
            changeLockingScript: nil,
            strategy: .sweepAll
        )
        let coinSelector = OpalBase.Address.Book.CoinSelector(
            utxos: [unspent],
            configuration: configuration,
            targetAmount: 1_000,
            feePerByte: 0,
            minimumRelayFeeRate: 0
        )

        #expect(throws: OpalBase.Transaction.Error.insufficientFunds(required: 500)) {
            _ = try coinSelector.select()
        }
    }

    @Test("evaluation rejects invalid excess scenarios", arguments: NilEvaluationCase.allCases)
    fileprivate func evaluationRejectsInvalidExcessScenarios(_ testCase: NilEvaluationCase) throws {
        let input = try testCase.makeInput()

        let evaluation = try OpalBase.Address.Book.CoinSelection.evaluate(
            configuration: input.configuration,
            total: input.total,
            inputCount: input.inputCount,
            targetAmount: input.targetAmount,
            minimumRelayFeeRate: input.minimumRelayFeeRate,
            feePerByte: input.feePerByte
        )

        #expect(evaluation == nil)
    }

    enum NilEvaluationCase: CaseIterable, CustomStringConvertible, Sendable {
        case tokenChangeDustDonation
        case excessWithoutChangeOutput

        var description: String {
            switch self {
            case .tokenChangeDustDonation:
                "tokenChangeDustDonation"
            case .excessWithoutChangeOutput:
                "excessWithoutChangeOutput"
            }
        }

        func makeInput() throws -> (
            configuration: OpalBase.Address.Book.CoinSelection.Configuration,
            total: UInt64,
            inputCount: Int,
            targetAmount: UInt64,
            minimumRelayFeeRate: UInt64,
            feePerByte: UInt64
        ) {
            let recipientOutputs = [
                OpalBase.Transaction.Output(value: 1_000, lockingScript: Data([0x51]))
            ]
            let feeWithoutChange = try OpalBase.Transaction.estimateFee(
                inputCount: 1,
                outputs: recipientOutputs,
                feePerByte: 1
            )

            switch self {
            case .tokenChangeDustDonation:
                let tokenChangeOutput = OpalBase.Transaction.Output(
                    value: 0,
                    lockingScript: Data([0x52]),
                    tokenData: try AddressBookCashTokensTestData.makeTokenData()
                )
                let outputsWithChange = recipientOutputs + [tokenChangeOutput]
                let configuration = OpalBase.Address.Book.CoinSelection.Configuration(
                    recipientOutputs: recipientOutputs,
                    outputsWithChange: outputsWithChange,
                    strategy: .greedyLargestFirst,
                    shouldAllowDustDonation: true,
                    tokenSelectionPolicy: .allowTokenUTXOs
                )
                return (configuration, 1_000 + feeWithoutChange + 100, 1, 1_000, 1, 1)
            case .excessWithoutChangeOutput:
                let configuration = OpalBase.Address.Book.CoinSelection.Configuration(
                    recipientOutputs: recipientOutputs,
                    changeLockingScript: nil,
                    strategy: .greedyLargestFirst,
                    shouldAllowDustDonation: false
                )
                return (configuration, 1_000 + feeWithoutChange + 1, 1, 1_000, 1, 1)
            }
        }
    }
}
