// Address+Book+UTXORepository~BookBridge.swift

import Foundation

extension Address.Book {
    func reserveUTXOs(_ utxos: Set<Transaction.Output.Unspent>) throws {
        try utxoStore.reserve(utxos)
    }
    
    func reserveUTXOs(_ utxos: Set<Transaction.Output.Unspent>,
                      tokenSelectionPolicy: Address.Book.CoinSelection.TokenSelectionPolicy) throws {
        try utxoStore.reserve(utxos, tokenSelectionPolicy: tokenSelectionPolicy)
    }
    
    func releaseUTXOs(_ utxos: Set<Transaction.Output.Unspent>) {
        utxoStore.release(utxos)
    }
    
    func addUTXO(_ utxo: Transaction.Output.Unspent) {
        utxoStore.add(utxo)
    }
    
    func addUTXOs(_ utxos: [Transaction.Output.Unspent]) {
        utxoStore.add(utxos)
    }
    
    func listUTXOs() -> Set<Transaction.Output.Unspent> {
        utxoStore.listUTXOs()
    }
    
    func listSpendableUTXOs() -> [Transaction.Output.Unspent] {
        utxoStore.listSpendableUTXOs()
    }
    
    func listUTXOs(for address: Address) -> [Transaction.Output.Unspent] {
        utxoStore.listUTXOs(for: address)
    }
    
    func replaceUTXOs(with utxos: Set<Transaction.Output.Unspent>) {
        utxoStore.replace(with: utxos)
    }
    
    func replaceUTXOs(for address: Address,
                      with utxos: [Transaction.Output.Unspent],
                      timestamp: Date = .now) throws -> Address.Book.UTXOChangeSet {
        let previous = listUTXOs(for: address)
        let orderedUTXOs = utxos.sorted { $0.compareOrder(before: $1) }
        utxoStore.replace(for: address, with: orderedUTXOs)
        return try Address.Book.UTXOChangeSet(address: address,
                                              previous: previous,
                                              updated: orderedUTXOs,
                                              timestamp: timestamp)
    }
    
    func removeUTXO(_ utxo: Transaction.Output.Unspent) {
        utxoStore.remove(utxo)
    }
    
    func findUTXO(matching input: Transaction.Input) -> Transaction.Output.Unspent? {
        utxoStore.findUTXO(matching: input)
    }
    
    func sortUTXOs(by areInIncreasingOrder: (Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool) -> [Transaction.Output.Unspent] {
        utxoStore.sortUTXOs(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: ((Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool)) async -> [Transaction.Output.Unspent] {
        utxoStore.sortSpendableUTXOs(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: ((Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool),
                            tokenSelectionPolicy: Address.Book.CoinSelection.TokenSelectionPolicy) -> [Transaction.Output.Unspent] {
        utxoStore.sortSpendableUTXOs(by: areInIncreasingOrder,
                                     tokenSelectionPolicy: tokenSelectionPolicy)
    }
}
