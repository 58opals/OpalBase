// OpalBase.Account~TokenGenesisSelection.swift

import Foundation

extension _OpalBase.Account {
    func selectGenesisInput(from spendable: [OpalBase.Transaction.OutputModel.UnspentModel]) -> OpalBase.Transaction.OutputModel.UnspentModel? {
        selectMaximumSpendableOutput(from: spendable) { output in
            output.tokenData == nil && output.previousTransactionOutputIndex == 0
        }
    }
    
    func selectGenesisInput() async -> OpalBase.Transaction.OutputModel.UnspentModel? {
        let spendableOutputs = await addressBook.listSpendableUTXOs()
        return selectGenesisInput(from: spendableOutputs)
    }
    
    func selectMaximumSpendableOutput(from spendableOutputs: [OpalBase.Transaction.OutputModel.UnspentModel],
                                      matching isEligible: (OpalBase.Transaction.OutputModel.UnspentModel) -> Bool)
    -> OpalBase.Transaction.OutputModel.UnspentModel? {
        var selected: OpalBase.Transaction.OutputModel.UnspentModel?
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
