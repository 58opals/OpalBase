// AddressBookCoinSelectorValidator+BranchAndBound.swift

import Foundation
import Testing
@testable import OpalBase

extension AddressBookCoinSelectorValidator {
    @Test("select branch and bound throws when minimal requirement overflows")
    func selectBranchAndBoundThrowsWhenMinimalRequirementOverflows() throws {
        let lockingScript = Data([0x51])
        let recipientOutputs = [OpalBase.Transaction.Output(value: 1, lockingScript: lockingScript)]
        let configuration = OpalBase.Address.Book.CoinSelection.Configuration(
            recipientOutputs: recipientOutputs,
            outputsWithChange: recipientOutputs,
            strategy: .branchAndBound
        )
        let feePerByte: UInt64 = 1
        let minimalFee = try OpalBase.Transaction.estimateFee(
            inputCount: 0,
            outputs: configuration.recipientOutputs,
            feePerByte: feePerByte
        )

        guard minimalFee > 0 else {
            throw BranchAndBoundFixtureFailure.expectedPositiveMinimalFee
        }

        let targetAmount = UInt64.max - (minimalFee - 1)
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let largeUnspent = OpalBase.Transaction.Output.Unspent(
            value: UInt64.max,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )

        let coinSelector = OpalBase.Address.Book.CoinSelector(
            utxos: [largeUnspent],
            configuration: configuration,
            targetAmount: targetAmount,
            feePerByte: feePerByte,
            minimumRelayFeeRate: 0
        )

        #expect(throws: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try coinSelector.select()
        }
    }

    @Test("branch and bound selection throws when suffix totals overflow UInt64", arguments: BranchAndBoundSuffixOverflowCase.allCases)
    fileprivate func selectBranchAndBoundDetectsSuffixOverflow(_ testCase: BranchAndBoundSuffixOverflowCase) {
        let selector = testCase.makeSelector()

        #expect(throws: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount) {
            _ = try selector.select()
        }
    }

    enum BranchAndBoundSuffixOverflowCase: CaseIterable, CustomStringConvertible, Sendable {
        case maximumThenOne
        case oneThenMaximum

        var description: String {
            switch self {
            case .maximumThenOne:
                "maximumThenOne"
            case .oneThenMaximum:
                "oneThenMaximum"
            }
        }

        func makeSelector() -> OpalBase.Address.Book.CoinSelector {
            let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
            let lockingScript = Data([0x51])

            switch self {
            case .maximumThenOne:
                let nearMaximumUnspent = OpalBase.Transaction.Output.Unspent(
                    value: UInt64.max,
                    lockingScript: lockingScript,
                    previousTransactionHash: previousTransactionHash,
                    previousTransactionOutputIndex: 0
                )
                let smallUnspent = OpalBase.Transaction.Output.Unspent(
                    value: 1,
                    lockingScript: lockingScript,
                    previousTransactionHash: previousTransactionHash,
                    previousTransactionOutputIndex: 1
                )
                let configuration = OpalBase.Address.Book.CoinSelection.Configuration(
                    recipientOutputs: .init(),
                    outputsWithChange: .init(),
                    strategy: .branchAndBound
                )
                return OpalBase.Address.Book.CoinSelector(
                    utxos: [nearMaximumUnspent, smallUnspent],
                    configuration: configuration,
                    targetAmount: 0,
                    feePerByte: 0,
                    minimumRelayFeeRate: 0
                )
            case .oneThenMaximum:
                let minimalUnspent = OpalBase.Transaction.Output.Unspent(
                    value: 1,
                    lockingScript: lockingScript,
                    previousTransactionHash: previousTransactionHash,
                    previousTransactionOutputIndex: 0
                )
                let maximumUnspent = OpalBase.Transaction.Output.Unspent(
                    value: UInt64.max,
                    lockingScript: lockingScript,
                    previousTransactionHash: previousTransactionHash,
                    previousTransactionOutputIndex: 1
                )
                let configuration = OpalBase.Address.Book.CoinSelection.Configuration.makeTemplateConfiguration(strategy: .branchAndBound)
                return OpalBase.Address.Book.CoinSelector(
                    utxos: [minimalUnspent, maximumUnspent],
                    configuration: configuration,
                    targetAmount: UInt64.max,
                    feePerByte: 0,
                    minimumRelayFeeRate: 0
                )
            }
        }
    }
}
