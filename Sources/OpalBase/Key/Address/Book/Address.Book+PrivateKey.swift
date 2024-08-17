import Foundation

extension Address.Book {
    private func getPrivateKey(for address: Address) throws -> PrivateKey {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        let privateKey = try generatePrivateKey(at: entry.derivationPath.index,
                                                for: entry.derivationPath.usage)
        return privateKey
    }
    
    func getPrivateKeys(for utxos: [Transaction.Output.Unspent]) throws -> [Transaction.Output.Unspent: PrivateKey] {
        var pair: [Transaction.Output.Unspent: PrivateKey] = [:]
        
        for utxo in utxos {
            let lockingScript = utxo.lockingScript
            let script = try Script.decode(lockingScript: lockingScript)
            let address = try Address(script: script)
            let privateKey = try getPrivateKey(for: address)
            pair[utxo] = privateKey
        }
        
        return pair
    }
}
