// Account+Snapshot.swift

import Foundation
import CryptoKit

extension Account {
    public struct Snapshot: Codable {
        public let purpose: DerivationPath.Purpose
        public let coinType: DerivationPath.CoinType
        public let account: UInt32
        public let addressBook: Address.Book.Snapshot
        
        public init(purpose: DerivationPath.Purpose,
                     coinType: DerivationPath.CoinType,
                     account: UInt32,
                     addressBook: Address.Book.Snapshot) {
            self.purpose = purpose
            self.coinType = coinType
            self.account = account
            self.addressBook = addressBook
        }
    }
}

extension Account.Snapshot {
    enum Error: Swift.Error {
        case missingCombinedData
    }
}

extension Account.Snapshot: Sendable {}

extension Account {
    public func getSnapshot() async -> Snapshot {
        let bookSnap = await addressBook.getSnapshot()
        return Snapshot(purpose: purpose,
                        coinType: coinType,
                        account: self.account.unhardenedIndex,
                        addressBook: bookSnap)
    }
    
    public func applySnapshot(_ snapshot: Snapshot) async throws {
        try await addressBook.applySnapshot(snapshot.addressBook)
    }
    
    public func saveSnapshot(to url: URL, using key: SymmetricKey? = nil) async throws {
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
    
    public func loadSnapshot(from url: URL, using key: SymmetricKey? = nil) async throws {
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
