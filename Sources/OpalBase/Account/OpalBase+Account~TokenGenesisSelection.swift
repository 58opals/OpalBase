// OpalBase+Account~TokenGenesisSelection.swift

import Foundation

extension _OpalBase.Account {
    func selectGenesisInput(from spendable: [OpalBase.Transaction.OutputModel.Unspent]) -> OpalBase.Transaction.OutputModel.Unspent? {
        selectMaximumSpendableOutput(from: spendable) { output in
            output.tokenData == nil && output.previousTransactionOutputIndex == 0
        }
    }
    
    func selectGenesisInput() async -> OpalBase.Transaction.OutputModel.Unspent? {
        let spendableOutputs = await addressBook.listSpendableUTXOs()
        return selectGenesisInput(from: spendableOutputs)
    }
    
    func selectMaximumSpendableOutput(from spendableOutputs: [OpalBase.Transaction.OutputModel.Unspent],
                                      matching isEligible: (OpalBase.Transaction.OutputModel.Unspent) -> Bool)
    -> OpalBase.Transaction.OutputModel.Unspent? {
        var selected: OpalBase.Transaction.OutputModel.Unspent?
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
