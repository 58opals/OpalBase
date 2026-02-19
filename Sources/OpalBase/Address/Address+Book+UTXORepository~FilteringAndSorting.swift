// Address+Book+UTXORepository~FilteringAndSorting.swift

import Foundation

extension Address.Book.UTXORepository {
    func listUTXOs() -> Set<Transaction.Output.Unspent> {
        allUTXOs
    }
    
    func listSpendableUTXOs() -> [Transaction.Output.Unspent] {
        spendableUTXOs.sorted { $0.compareOrder(before: $1) }
    }
    
    func listUTXOs(for address: Address) -> [Transaction.Output.Unspent] {
        let lockingScript = address.lockingScript.data
        guard let utxos = utxosByLockingScript[lockingScript] else {
            return .init()
        }
        return utxos.sorted { $0.compareOrder(before: $1) }
    }
    
    func sortUTXOs(by areInIncreasingOrder: (Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool) -> [Transaction.Output.Unspent] {
        allUTXOs.sorted(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: (Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool) -> [Transaction.Output.Unspent] {
        spendableUTXOs.sorted(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: (Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool,
                            tokenSelectionPolicy: Address.Book.CoinSelection.TokenSelectionPolicy) -> [Transaction.Output.Unspent] {
        let filteredSpendable = filterUTXOs(spendableUTXOs, tokenSelectionPolicy: tokenSelectionPolicy)
        return filteredSpendable.sorted(by: areInIncreasingOrder)
    }
    
    var allUTXOs: Set<Transaction.Output.Unspent> {
        Set(utxosByOutpoint.values)
    }
    
    var spendableUTXOs: Set<Transaction.Output.Unspent> {
        var spendable = allUTXOs
        spendable.subtract(reservedUTXOs)
        return spendable
    }
    
    func filterUTXOs(_ utxos: Set<Transaction.Output.Unspent>,
                     tokenSelectionPolicy: Address.Book.CoinSelection.TokenSelectionPolicy) -> Set<Transaction.Output.Unspent> {
        switch tokenSelectionPolicy {
        case .excludeTokenUTXOs:
            return Set(utxos.filter { $0.tokenData == nil })
        case .allowTokenUTXOs:
            return utxos
        }
    }
}
