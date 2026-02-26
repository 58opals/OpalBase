// AccountActor~TokenGenesisSelection.swift

import Foundation

extension AccountActor {
    func selectGenesisInput(from spendable: [TransactionModel.OutputModel.UnspentModel]) -> TransactionModel.OutputModel.UnspentModel? {
        selectMaximumSpendableOutput(from: spendable) { output in
            output.tokenData == nil && output.previousTransactionOutputIndex == 0
        }
    }
    
    func selectGenesisInput() async -> TransactionModel.OutputModel.UnspentModel? {
        let spendableOutputs = await addressBook.listSpendableUTXOs()
        return selectGenesisInput(from: spendableOutputs)
    }
    
    func selectMaximumSpendableOutput(from spendableOutputs: [TransactionModel.OutputModel.UnspentModel],
                                      matching isEligible: (TransactionModel.OutputModel.UnspentModel) -> Bool)
    -> TransactionModel.OutputModel.UnspentModel? {
        var selected: TransactionModel.OutputModel.UnspentModel?
        for output in spendableOutputs where isEligible(output) {
            guard let current = selected else {
                selected = output
                continue
            }
            if output.value > current.value
                || (output.value == current.value && output.compareOrder(before: current)) {
                selected = output
            }
        }
        return selected
    }
}
