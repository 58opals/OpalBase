// AddressModel+BookActor+UTXORepository~FilteringAndSorting.swift

import Foundation

extension AddressModel.BookActor.UTXORepository {
    func listUTXOs() -> Set<TransactionModel.OutputModel.UnspentModel> {
        allUTXOs
    }
    
    func listSpendableUTXOs() -> [TransactionModel.OutputModel.UnspentModel] {
        spendableUTXOs.sorted { $0.compareOrder(before: $1) }
    }
    
    func listUTXOs(for address: AddressModel) -> [TransactionModel.OutputModel.UnspentModel] {
        let lockingScript = address.lockingScript.data
        guard let utxos = utxosByLockingScript[lockingScript] else {
            return .init()
        }
        return utxos.sorted { $0.compareOrder(before: $1) }
    }
    
    func sortUTXOs(by areInIncreasingOrder: (TransactionModel.OutputModel.UnspentModel, TransactionModel.OutputModel.UnspentModel) -> Bool) -> [TransactionModel.OutputModel.UnspentModel] {
        allUTXOs.sorted(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: (TransactionModel.OutputModel.UnspentModel, TransactionModel.OutputModel.UnspentModel) -> Bool) -> [TransactionModel.OutputModel.UnspentModel] {
        spendableUTXOs.sorted(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: (TransactionModel.OutputModel.UnspentModel, TransactionModel.OutputModel.UnspentModel) -> Bool,
                            tokenSelectionPolicy: AddressModel.BookActor.CoinSelectionModel.TokenSelectionPolicy) -> [TransactionModel.OutputModel.UnspentModel] {
        let filteredSpendable = filterUTXOs(spendableUTXOs, tokenSelectionPolicy: tokenSelectionPolicy)
        return filteredSpendable.sorted(by: areInIncreasingOrder)
    }
    
    var allUTXOs: Set<TransactionModel.OutputModel.UnspentModel> {
        Set(utxosByOutpoint.values)
    }
    
    var spendableUTXOs: Set<TransactionModel.OutputModel.UnspentModel> {
        var spendable = allUTXOs
        spendable.subtract(reservedUTXOs)
        return spendable
    }
    
    func filterUTXOs(_ utxos: Set<TransactionModel.OutputModel.UnspentModel>,
                     tokenSelectionPolicy: AddressModel.BookActor.CoinSelectionModel.TokenSelectionPolicy) -> Set<TransactionModel.OutputModel.UnspentModel> {
        switch tokenSelectionPolicy {
        case .excludeTokenUTXOs:
            return Set(utxos.filter { $0.tokenData == nil })
        case .allowTokenUTXOs:
            return utxos
        }
    }
}
