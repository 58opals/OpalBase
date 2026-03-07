// OpalBase.Address+BookActor+UTXORepository~FilteringAndSorting.swift

import Foundation

extension _OpalBase.Address.Book.UTXORepository {
    func listUTXOs() -> Set<OpalBase.Transaction.OutputModel.UnspentModel> {
        allUTXOs
    }
    
    func listSpendableUTXOs() -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        spendableUTXOs.sorted { $0.compareOrder(before: $1) }
    }
    
    func listUTXOs(for address: OpalBase.Address) -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        let lockingScript = address.lockingScript.data
        guard let utxos = utxosByLockingScript[lockingScript] else {
            return .init()
        }
        return utxos.sorted { $0.compareOrder(before: $1) }
    }
    
    func sortUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.OutputModel.UnspentModel, OpalBase.Transaction.OutputModel.UnspentModel) -> Bool) -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        allUTXOs.sorted(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.OutputModel.UnspentModel, OpalBase.Transaction.OutputModel.UnspentModel) -> Bool) -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        spendableUTXOs.sorted(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.OutputModel.UnspentModel, OpalBase.Transaction.OutputModel.UnspentModel) -> Bool,
                            tokenSelectionPolicy: OpalBase.Address.Book.CoinSelectionModel.TokenSelectionPolicy) -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        let filteredSpendable = filterUTXOs(spendableUTXOs, tokenSelectionPolicy: tokenSelectionPolicy)
        return filteredSpendable.sorted(by: areInIncreasingOrder)
    }
    
    var allUTXOs: Set<OpalBase.Transaction.OutputModel.UnspentModel> {
        Set(utxosByOutpoint.values)
    }
    
    var spendableUTXOs: Set<OpalBase.Transaction.OutputModel.UnspentModel> {
        var spendable = allUTXOs
        spendable.subtract(reservedUTXOs)
        return spendable
    }
    
    func filterUTXOs(_ utxos: Set<OpalBase.Transaction.OutputModel.UnspentModel>,
                     tokenSelectionPolicy: OpalBase.Address.Book.CoinSelectionModel.TokenSelectionPolicy) -> Set<OpalBase.Transaction.OutputModel.UnspentModel> {
        switch tokenSelectionPolicy {
        case .excludeTokenUTXOs:
            return Set(utxos.filter { $0.tokenData == nil })
        case .allowTokenUTXOs:
            return utxos
        }
    }
}
