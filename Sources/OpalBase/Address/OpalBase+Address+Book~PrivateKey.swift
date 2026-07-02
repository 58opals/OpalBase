// OpalBase+Address+Book~PrivateKey.swift

import Foundation

extension _OpalBase.Address.Book {
    private func loadSigningKey(for entry: Entry) throws -> OpalBase.Key.SigningKey {
        return try generateSigningKey(
            at: entry.derivationPath.index,
            for: entry.derivationPath.usage
        )
    }

    func deriveSigningKeys(for utxos: [OpalBase.Transaction.Output.Unspent]) throws -> [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey] {
        var derived: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey] = .init()
        derived.reserveCapacity(utxos.count)

        let entries = listAllEntries()
        var entryByLockingScript: [Data: Entry] = .init()
        entryByLockingScript.reserveCapacity(entries.count)
        for entry in entries {
            entryByLockingScript[entry.address.lockingScript.data] = entry
        }

        var signingKeyByLockingScript: [Data: OpalBase.Key.SigningKey] = .init()
        signingKeyByLockingScript.reserveCapacity(utxos.count)

        for utxo in utxos {
            let lockingScript = utxo.lockingScript
            guard let entry = entryByLockingScript[lockingScript] else { throw Error.entryNotFound }

            let signingKey: OpalBase.Key.SigningKey
            if let cachedSigningKey = signingKeyByLockingScript[lockingScript] {
                signingKey = cachedSigningKey
            } else {
                signingKey = try loadSigningKey(for: entry)
                signingKeyByLockingScript[lockingScript] = signingKey
            }

            derived[utxo] = signingKey
        }

        return derived
    }
}
