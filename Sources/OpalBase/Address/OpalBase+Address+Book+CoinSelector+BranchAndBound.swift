// OpalBase+Address+Book+CoinSelector+BranchAndBound.swift

import Foundation

extension _OpalBase.Address.Book.CoinSelector {
    func selectBranchAndBound(searchNodeCountLimit: Int? = nil) throws -> [OpalBase.Transaction.Output.Unspent] {
        let maximumSearchNodeCount = 100_000
        let effectiveSearchNodeCountLimit = min(
            max(searchNodeCountLimit ?? maximumSearchNodeCount, 0),
            maximumSearchNodeCount
        )
        let suffixTotals = try makeSuffixTotals()

        var bestSelection: [OpalBase.Transaction.Output.Unspent] = .init()
        var bestEvaluation: OpalBase.Address.Book.CoinSelection.Evaluation?
        var searchNodes: [(
            nextUnspentOutputIndex: Int,
            sum: UInt64,
            selectedUnspentOutputCount: Int,
            parentSearchNodeIndex: Int?,
            includedUnspentOutputIndex: Int?
        )] = [(0, 0, 0, nil, nil)]
        var pendingSearchNodeIndices: [Int] = [0]
        var visitedSearchNodeCount = 0

        func makeGreedyFallbackSelection() throws -> [OpalBase.Transaction.Output.Unspent]? {
            var selection: [OpalBase.Transaction.Output.Unspent] = .init()
            var sum: UInt64 = 0
            if try evaluate(selection: selection, sum: sum) != nil {
                return selection
            }

            for unspentOutput in utxos {
                selection.append(unspentOutput)
                sum = try sum.addOrThrow(
                    unspentOutput.value,
                    overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount
                )
                if try evaluate(selection: selection, sum: sum) != nil {
                    return selection
                }
            }

            return nil
        }

        func makeSelection(endingAt searchNodeIndex: Int) -> [OpalBase.Transaction.Output.Unspent] {
            var selectedUnspentOutputIndices: [Int] = .init()
            var currentSearchNodeIndex: Int? = searchNodeIndex
            while let index = currentSearchNodeIndex {
                let searchNode = searchNodes[index]
                if let includedUnspentOutputIndex = searchNode.includedUnspentOutputIndex {
                    selectedUnspentOutputIndices.append(includedUnspentOutputIndex)
                }
                currentSearchNodeIndex = searchNode.parentSearchNodeIndex
            }

            return selectedUnspentOutputIndices.reversed().map { utxos[$0] }
        }

        func updateBest(searchNodeIndex: Int) throws {
            let searchNode = searchNodes[searchNodeIndex]
            guard let evaluation = try OpalBase.Address.Book.CoinSelection.evaluate(
                configuration: configuration,
                total: searchNode.sum,
                inputCount: searchNode.selectedUnspentOutputCount,
                targetAmount: targetAmount,
                minimumRelayFeeRate: minimumRelayFeeRate,
                feePerByte: feePerByte
            ) else {
                return
            }

            if let currentBest = bestEvaluation {
                if evaluation.excess < currentBest.excess {
                    bestEvaluation = evaluation
                    bestSelection = makeSelection(endingAt: searchNodeIndex)
                } else if evaluation.excess == currentBest.excess,
                          searchNode.selectedUnspentOutputCount < bestSelection.count {
                    bestEvaluation = evaluation
                    bestSelection = makeSelection(endingAt: searchNodeIndex)
                }
            } else {
                bestEvaluation = evaluation
                bestSelection = makeSelection(endingAt: searchNodeIndex)
            }
        }

        while visitedSearchNodeCount < effectiveSearchNodeCountLimit,
              let searchNodeIndex = pendingSearchNodeIndices.popLast() {
            visitedSearchNodeCount += 1
            try updateBest(searchNodeIndex: searchNodeIndex)

            let searchNode = searchNodes[searchNodeIndex]
            if let currentBest = bestEvaluation,
               currentBest.excess == 0,
               searchNode.selectedUnspentOutputCount >= bestSelection.count {
                continue
            }

            let nextUnspentOutputIndex = searchNode.nextUnspentOutputIndex
            guard nextUnspentOutputIndex < utxos.count else { continue }

            let remaining = suffixTotals[nextUnspentOutputIndex]
            let minimalFee = try OpalBase.Transaction.estimateFee(
                inputCount: searchNode.selectedUnspentOutputCount,
                outputs: configuration.recipientOutputs,
                feePerByte: feePerByte
            )
            let minimalRequirement = try targetAmount.addOrThrow(
                minimalFee,
                overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount
            )
            let sumWithRemaining = try searchNode.sum.addOrThrow(
                remaining,
                overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount
            )
            guard sumWithRemaining >= minimalRequirement else { continue }

            let followingUnspentOutputIndex = nextUnspentOutputIndex + 1
            let excludedSearchNodeIndex = searchNodes.count
            searchNodes.append((
                followingUnspentOutputIndex,
                searchNode.sum,
                searchNode.selectedUnspentOutputCount,
                searchNodeIndex,
                nil
            ))
            pendingSearchNodeIndices.append(excludedSearchNodeIndex)

            let sumIncludingCurrent = try searchNode.sum.addOrThrow(
                utxos[nextUnspentOutputIndex].value,
                overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount
            )
            let includedSearchNodeIndex = searchNodes.count
            searchNodes.append((
                followingUnspentOutputIndex,
                sumIncludingCurrent,
                searchNode.selectedUnspentOutputCount + 1,
                searchNodeIndex,
                nextUnspentOutputIndex
            ))
            pendingSearchNodeIndices.append(includedSearchNodeIndex)
        }

        if bestEvaluation == nil,
           !pendingSearchNodeIndices.isEmpty,
           let fallbackSelection = try makeGreedyFallbackSelection() {
            return fallbackSelection
        }

        guard bestEvaluation != nil else { throw OpalBase.Address.Book.Error.insufficientFunds }
        return bestSelection
    }
}
