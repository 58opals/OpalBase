// Address+Book~PrivateKey.swift

import Foundation

extension Address.Book {
    private func loadPrivateKey(for address: Address) throws -> PrivateKey {
        guard let entry = inventory.findEntry(for: address) else { throw Error.entryNotFound }
        let privateKey = try generatePrivateKey(at: entry.derivationPath.index,
                                                for: entry.derivationPath.usage)
        return privateKey
    }
    
    func derivePrivateKeys(for unspentTransactionOutputs: [Transaction.Output.Unspent]) throws -> [Transaction.Output.Unspent: PrivateKey] {
        var pair: [Transaction.Output.Unspent: PrivateKey] = .init()
        
        for unspentTransactionOutput in unspentTransactionOutputs {
            let lockingScript = unspentTransactionOutput.lockingScript
            let script = try Script.decode(lockingScript: lockingScript)
            let address = try Address(script: script)
            let privateKey = try loadPrivateKey(for: address)
            pair[unspentTransactionOutput] = privateKey
        }
        
        return pair
    }
}
