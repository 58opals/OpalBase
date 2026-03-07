// AddressModel+BookActor~BookBridge.swift

import Foundation

extension AddressModel.BookActor {
    func reserveUTXOs(_ utxos: Set<TransactionModel.OutputModel.UnspentModel>) throws {
        try utxoStore.reserve(utxos)
    }
    
    func reserveUTXOs(_ utxos: Set<TransactionModel.OutputModel.UnspentModel>,
                      tokenSelectionPolicy: AddressModel.BookActor.CoinSelectionModel.TokenSelectionPolicy) throws {
        try utxoStore.reserve(utxos, tokenSelectionPolicy: tokenSelectionPolicy)
    }
    
    func releaseUTXOs(_ utxos: Set<TransactionModel.OutputModel.UnspentModel>) {
        utxoStore.release(utxos)
    }
    
    func addUTXO(_ utxo: TransactionModel.OutputModel.UnspentModel) {
        utxoStore.add(utxo)
    }
    
    func addUTXOs(_ utxos: [TransactionModel.OutputModel.UnspentModel]) {
        utxoStore.add(utxos)
    }
    
    func listUTXOs() -> Set<TransactionModel.OutputModel.UnspentModel> {
        utxoStore.listUTXOs()
    }
    
    func listSpendableUTXOs() -> [TransactionModel.OutputModel.UnspentModel] {
        utxoStore.listSpendableUTXOs()
    }
    
    func listUTXOs(for address: AddressModel) -> [TransactionModel.OutputModel.UnspentModel] {
        utxoStore.listUTXOs(for: address)
    }
    
    func replaceUTXOs(with utxos: Set<TransactionModel.OutputModel.UnspentModel>) {
        utxoStore.replace(with: utxos)
    }
    
    func replaceUTXOs(for address: AddressModel,
                      with utxos: [TransactionModel.OutputModel.UnspentModel],
                      timestamp: Date = .now) throws -> AddressModel.BookActor.UTXOChangeSetModel {
        let previous = listUTXOs(for: address)
        let orderedUTXOs = utxos.sorted { $0.compareOrder(before: $1) }
        utxoStore.replace(for: address, with: orderedUTXOs)
        return try AddressModel.BookActor.UTXOChangeSetModel(address: address,
                                              previous: previous,
                                              updated: orderedUTXOs,
                                              timestamp: timestamp)
    }
    
    func removeUTXO(_ utxo: TransactionModel.OutputModel.UnspentModel) {
        utxoStore.remove(utxo)
    }
    
    func findUTXO(matching input: TransactionModel.InputModel) -> TransactionModel.OutputModel.UnspentModel? {
        utxoStore.findUTXO(matching: input)
    }
    
    func sortUTXOs(by areInIncreasingOrder: (TransactionModel.OutputModel.UnspentModel, TransactionModel.OutputModel.UnspentModel) -> Bool) -> [TransactionModel.OutputModel.UnspentModel] {
        utxoStore.sortUTXOs(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: ((TransactionModel.OutputModel.UnspentModel, TransactionModel.OutputModel.UnspentModel) -> Bool)) async -> [TransactionModel.OutputModel.UnspentModel] {
        utxoStore.sortSpendableUTXOs(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: ((TransactionModel.OutputModel.UnspentModel, TransactionModel.OutputModel.UnspentModel) -> Bool),
                            tokenSelectionPolicy: AddressModel.BookActor.CoinSelectionModel.TokenSelectionPolicy) -> [TransactionModel.OutputModel.UnspentModel] {
        utxoStore.sortSpendableUTXOs(by: areInIncreasingOrder,
                                     tokenSelectionPolicy: tokenSelectionPolicy)
    }
}

