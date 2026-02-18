// Account~TokenGenesisSelection.swift

import Foundation

extension Account {
    func selectGenesisInput(from spendable: [Transaction.Output.Unspent]) -> Transaction.Output.Unspent? {
        selectMaximumSpendableOutput(from: spendable) { output in
            output.tokenData == nil && output.previousTransactionOutputIndex == 0
        }
    }
    
    func selectGenesisInput() async -> Transaction.Output.Unspent? {
        let spendableOutputs = await addressBook.listSpendableUTXOs()
        return selectGenesisInput(from: spendableOutputs)
    }
    
    func selectMaximumSpendableOutput(from spendableOutputs: [Transaction.Output.Unspent],
                                      matching isEligible: (Transaction.Output.Unspent) -> Bool)
    -> Transaction.Output.Unspent? {
        var selected: Transaction.Output.Unspent?
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
