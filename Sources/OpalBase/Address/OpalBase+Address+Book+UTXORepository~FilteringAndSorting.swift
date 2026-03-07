// OpalBase+Address+Book+UTXORepository~FilteringAndSorting.swift

import Foundation

extension _OpalBase.Address.Book.UTXORepository {
    func listUTXOs() -> Set<OpalBase.Transaction.OutputModel.Unspent> {
        allUTXOs
    }
    
    func listSpendableUTXOs() -> [OpalBase.Transaction.OutputModel.Unspent] {
        spendableUTXOs.sorted { $0.compareOrder(before: $1) }
    }
    
    func listUTXOs(for address: OpalBase.Address) -> [OpalBase.Transaction.OutputModel.Unspent] {
        let lockingScript = address.lockingScript.data
        guard let utxos = utxosByLockingScript[lockingScript] else {
            return .init()
        }
        return utxos.sorted { $0.compareOrder(before: $1) }
    }
    
    func sortUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.OutputModel.Unspent, OpalBase.Transaction.OutputModel.Unspent) -> Bool) -> [OpalBase.Transaction.OutputModel.Unspent] {
        allUTXOs.sorted(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.OutputModel.Unspent, OpalBase.Transaction.OutputModel.Unspent) -> Bool) -> [OpalBase.Transaction.OutputModel.Unspent] {
        spendableUTXOs.sorted(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.OutputModel.Unspent, OpalBase.Transaction.OutputModel.Unspent) -> Bool,
                            tokenSelectionPolicy: OpalBase.Address.Book.CoinSelectionModel.TokenSelectionPolicy) -> [OpalBase.Transaction.OutputModel.Unspent] {
        let filteredSpendable = filterUTXOs(spendableUTXOs, tokenSelectionPolicy: tokenSelectionPolicy)
        return filteredSpendable.sorted(by: areInIncreasingOrder)
    }
    
    var allUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent> {
        Set(utxosByOutpoint.values)
    }
    
    var spendableUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent> {
        var spendable = allUTXOs
        spendable.subtract(reservedUTXOs)
        return spendable
    }
    
    func filterUTXOs(_ utxos: Set<OpalBase.Transaction.OutputModel.Unspent>,
                     tokenSelectionPolicy: OpalBase.Address.Book.CoinSelectionModel.TokenSelectionPolicy) -> Set<OpalBase.Transaction.OutputModel.Unspent> {
        switch tokenSelectionPolicy {
        case .excludeTokenUTXOs:
            return Set(utxos.filter { $0.tokenData == nil })
        case .allowTokenUTXOs:
            return utxos
        }
    }
}
