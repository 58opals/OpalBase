// Address+Book~PrivateKey.swift

import Foundation

extension Address.Book {
    private func loadPrivateKey(for address: Address) throws -> PrivateKey {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        let privateKey = try generatePrivateKey(at: entry.derivationPath.index,
                                                for: entry.derivationPath.usage)
        return privateKey
    }
    
    func derivePrivateKeys(for utxos: [Transaction.Output.Unspent]) throws -> [Transaction.Output.Unspent: PrivateKey] {
        var derived: [Transaction.Output.Unspent: PrivateKey] = .init()
        derived.reserveCapacity(utxos.count)
        
        var addressByLockingScript: [Data: Address] = .init()
        addressByLockingScript.reserveCapacity(utxos.count)
        
        var privateKeyByAddress: [Address: PrivateKey] = .init()
        privateKeyByAddress.reserveCapacity(utxos.count)
        
        for utxo in utxos {
            let lockingScript = utxo.lockingScript
            let address: Address
            if let cachedAddress = addressByLockingScript[lockingScript] {
                address = cachedAddress
            } else {
                let script = try Script.decode(lockingScript: lockingScript)
                address = try Address(script: script)
                addressByLockingScript[lockingScript] = address
            }
            
            let privateKey: PrivateKey
            if let cachedPrivateKey = privateKeyByAddress[address] {
                privateKey = cachedPrivateKey
            } else {
                privateKey = try loadPrivateKey(for: address)
                privateKeyByAddress[address] = privateKey
            }
            
            derived[utxo] = privateKey
        }
        
        return derived
    }
}
