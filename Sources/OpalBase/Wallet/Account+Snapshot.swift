// Account+Snapshot.swift

import Foundation
import CryptoKit

extension Account {
    struct Snapshot: Codable {
        var purpose: DerivationPath.Purpose
        var coinType: DerivationPath.CoinType
        var account: UInt32
        var addressBook: Address.Book.Snapshot
    }
}

extension Account {
    func getSnapshot() async -> Snapshot {
        let bookSnap = await addressBook.getSnapshot()
        return Snapshot(purpose: purpose,
                        coinType: coinType,
                        account: self.account.unhardenedIndex,
                        addressBook: bookSnap)
    }
    
    func applySnapshot(_ snapshot: Snapshot) async throws {
        try await addressBook.applySnapshot(snapshot.addressBook)
    }
    
    func saveSnapshot(to url: URL, using key: SymmetricKey? = nil) async throws {
        let data = try JSONEncoder().encode(await getSnapshot())
        let output: Data
        if let key {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { throw Snapshot.Error.missingCombinedData }
            output = combined
        } else {
            output = data
        }
        try output.write(to: url)
    }
    
    func loadSnapshot(from url: URL, using key: SymmetricKey? = nil) async throws {
        let data = try Data(contentsOf: url)
        let input: Data
        if let key {
            let sealed = try AES.GCM.SealedBox(combined: data)
            input = try AES.GCM.open(sealed, using: key)
        } else {
            input = data
        }
        let snap = try JSONDecoder().decode(Snapshot.self, from: input)
        try await applySnapshot(snap)
    }
}
