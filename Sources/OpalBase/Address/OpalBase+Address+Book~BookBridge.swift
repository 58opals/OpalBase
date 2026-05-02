// OpalBase+Address+Book~BookBridge.swift

import Foundation

extension _OpalBase.Address.Book {
    func reserveUTXOs(_ utxos: Set<OpalBase.Transaction.Output.Unspent>) throws {
        try utxoStore.reserve(utxos)
    }
    
    func reserveUTXOs(_ utxos: Set<OpalBase.Transaction.Output.Unspent>,
                      tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy) throws {
        try utxoStore.reserve(utxos, tokenSelectionPolicy: tokenSelectionPolicy)
    }
    
    func releaseUTXOs(_ utxos: Set<OpalBase.Transaction.Output.Unspent>) {
        utxoStore.release(utxos)
    }
    
    func addUTXO(_ utxo: OpalBase.Transaction.Output.Unspent) {
        utxoStore.add(utxo)
    }
    
    func addUTXOs(_ utxos: [OpalBase.Transaction.Output.Unspent]) {
        utxoStore.add(utxos)
    }
    
    func listUTXOs() -> Set<OpalBase.Transaction.Output.Unspent> {
        utxoStore.listUTXOs()
    }
    
    func listSpendableUTXOs() -> [OpalBase.Transaction.Output.Unspent] {
        utxoStore.listSpendableUTXOs()
    }
    
    func listUTXOs(for address: OpalBase.Address) -> [OpalBase.Transaction.Output.Unspent] {
        utxoStore.listUTXOs(for: address)
    }
    
    func replaceUTXOs(with utxos: Set<OpalBase.Transaction.Output.Unspent>) {
        utxoStore.replace(with: utxos)
    }
    
    func makeUTXOChangeSet(for address: OpalBase.Address,
                           with utxos: [OpalBase.Transaction.Output.Unspent],
                           timestamp: Date = .now) throws -> OpalBase.Address.Book.UTXOChangeSet {
        let previous = listUTXOs(for: address)
        let orderedUTXOs = utxos.sorted { $0.compareOrder(before: $1) }
        return try OpalBase.Address.Book.UTXOChangeSet(address: address,
                                              previous: previous,
                                              updated: orderedUTXOs,
                                              timestamp: timestamp)
    }
    
    func replaceUTXOs(for address: OpalBase.Address,
                      with utxos: [OpalBase.Transaction.Output.Unspent],
                      timestamp: Date = .now) throws -> OpalBase.Address.Book.UTXOChangeSet {
        let changeSet = try makeUTXOChangeSet(for: address,
                                              with: utxos,
                                              timestamp: timestamp)
        replaceUTXOs(for: address, withValidated: changeSet.updated)
        return changeSet
    }

    func replaceUTXOs(for address: OpalBase.Address,
                      withValidated utxos: [OpalBase.Transaction.Output.Unspent]) {
        utxoStore.replace(for: address, with: utxos)
    }

    func removeUTXO(_ utxo: OpalBase.Transaction.Output.Unspent) {
        utxoStore.remove(utxo)
    }
    
    func findUTXO(matching input: OpalBase.Transaction.Input) -> OpalBase.Transaction.Output.Unspent? {
        utxoStore.findUTXO(matching: input)
    }
    
    func sortUTXOs(by areInIncreasingOrder: (OpalBase.Transaction.Output.Unspent, OpalBase.Transaction.Output.Unspent) -> Bool) -> [OpalBase.Transaction.Output.Unspent] {
        utxoStore.sortUTXOs(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: ((OpalBase.Transaction.Output.Unspent, OpalBase.Transaction.Output.Unspent) -> Bool)) async -> [OpalBase.Transaction.Output.Unspent] {
        utxoStore.sortSpendableUTXOs(by: areInIncreasingOrder)
    }
    
    func sortSpendableUTXOs(by areInIncreasingOrder: ((OpalBase.Transaction.Output.Unspent, OpalBase.Transaction.Output.Unspent) -> Bool),
                            tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy) -> [OpalBase.Transaction.Output.Unspent] {
        utxoStore.sortSpendableUTXOs(by: areInIncreasingOrder,
                                     tokenSelectionPolicy: tokenSelectionPolicy)
    }
}
