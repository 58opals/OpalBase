// Account~TokenGenesisSelection.swift

import Foundation

extension Account {
    func selectGenesisInput(from spendable: [Transaction.Output.Unspent]) -> Transaction.Output.Unspent? {
        spendable.first { $0.tokenData == nil && $0.previousTransactionOutputIndex == 0 }
    }
    
    func selectGenesisInput() async -> Transaction.Output.Unspent? {
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        return selectGenesisInput(from: spendableOutputs)
    }
}
