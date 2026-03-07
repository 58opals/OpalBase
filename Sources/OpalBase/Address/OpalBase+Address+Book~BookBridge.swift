// OpalBase+Address+Book~BookBridge.swift

import Foundation

extension _OpalBase.Address.Book {
    func reserveUTXOs(_ utxos: Set<OpalBase.Transaction.OutputModel.UnspentModel>) throws {
        try utxoStore.reserve(utxos)
    }
    
    func reserveUTXOs(_ utxos: Set<OpalBase.Transaction.OutputModel.UnspentModel>,
                      tokenSelectionPolicy: OpalBase.Address.Book.CoinSelectionModel.TokenSelectionPolicy) throws {
        try utxoStore.reserve(utxos, tokenSelectionPolicy: tokenSelectionPolicy)
    }
    
    func releaseUTXOs(_ utxos: Set<OpalBase.Transaction.OutputModel.UnspentModel>) {
        utxoStore.release(utxos)
    }
    
    func addUTXO(_ utxo: OpalBase.Transaction.OutputModel.UnspentModel) {
        utxoStore.add(utxo)
    }
    
    func addUTXOs(_ utxos: [OpalBase.Transaction.OutputModel.UnspentModel]) {
        utxoStore.add(utxos)
    }
    
    func listUTXOs() -> Set<OpalBase.Transaction.OutputModel.UnspentModel> {
        utxoStore.listUTXOs()
    }
    
    func listSpendableUTXOs() -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        utxoStore.listSpendableUTXOs()
    }
    
    func listUTXOs(for address: OpalBase.Address) -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        utxoStore.listUTXOs(for: address)
    }
    
    func replaceUTXOs(with utxos: Set<OpalBase.Transaction.OutputModel.UnspentModel>) {
        utxoStore.replace(with: utxos)
    }
    
    func replaceUTXOs(for address: OpalBase.Address,
                      with utxos: [OpalBase.Transaction.OutputModel.UnspentModel],
                      timestamp: Date = .now) throws -> OpalBase.Address.Book.UTXOChangeSetModel {
        let previous = listUTXOs(for: address)
        let orderedUTXOs = utxos.sorted { $0.compareOrder(before: $1) }
        utxoStore.replace(for: address, with: orderedUTXOs)
        return try OpalBase.Address.Book.UTXOChangeSetModel(address: address,
                                              previous: previous,
                                              updated: orderedUTXOs,
                                              timestamp: timestamp)
    }
    
    func removeUTXO(_ utxo: OpalBase.Transaction.OutputModel.UnspentModel) {
        utxoStore.remove(utxo)
    }
    
    func findUTXO(matching input: OpalBase.Transaction.InputModel) -> OpalBase.Transaction.OutputModel.UnspentModel? {
        utxoStore.findUTXO(matching: input)
    }
    
    func sortUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.OutputModel.UnspentModel, OpalBase.Transaction.OutputModel.UnspentModel) -> Bool) -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        utxoStore.sortUTXOs(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: ((OpalBase.Transaction.OutputModel.UnspentModel, OpalBase.Transaction.OutputModel.UnspentModel) -> Bool)) async -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        utxoStore.sortSpendableUTXOs(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: ((OpalBase.Transaction.OutputModel.UnspentModel, OpalBase.Transaction.OutputModel.UnspentModel) -> Bool),
                            tokenSelectionPolicy: OpalBase.Address.Book.CoinSelectionModel.TokenSelectionPolicy) -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        utxoStore.sortSpendableUTXOs(by: areInIncreasingOrder,
                                     tokenSelectionPolicy: tokenSelectionPolicy)
    }
}

