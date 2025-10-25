// Account+Outbox.swift

import Foundation

extension Account {
    actor Outbox {
        private let folderURL: URL
        private let fileManager = FileManager.default
        
        init(folderURL: URL) throws {
            self.folderURL = folderURL
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
    }
}

extension Account.Outbox {
    func save(transactionData: Data) async throws {
        let hash = Transaction.Hash(naturalOrder: HASH256.hash(transactionData))
        let url = folderURL.appendingPathComponent(hash.naturalOrder.hexadecimalString)
        try transactionData.write(to: url)
    }
    
    func remove(transactionHash: Transaction.Hash) async {
        let url = folderURL.appendingPathComponent(transactionHash.naturalOrder.hexadecimalString)
        try? fileManager.removeItem(at: url)
    }
}

extension Account.Outbox {
    func purgeTransactions() async {
        guard let urls = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return }
        for url in urls { try? fileManager.removeItem(at: url) }
    }
}

extension Account {
    func purgeOutbox() async {
        await outbox.purgeTransactions()
    }
}
