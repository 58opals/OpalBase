// Account+TokenGenesis~Selection.swift

import Foundation

extension Account {
    func selectGenesisInput(from spendable: [Transaction.Output.Unspent]) async -> Transaction.Output.Unspent? {
        let spendableSet = Set(spendable)
        let sortedSpendable = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        return sortedSpendable
            .filter { spendableSet.contains($0) }
            .filter { $0.tokenData == nil }
            .first { $0.previousTransactionOutputIndex == 0 }
    }
    
    func selectGenesisInput() async -> Transaction.Output.Unspent? {
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        return await selectGenesisInput(from: spendableOutputs)
    }
}
