// Account+Outbox.swift

import Foundation

extension Account {
    actor Outbox {
        private let folderURL: URL
        private let fileManager = FileManager.default
        private var pendingTransactions: [Transaction.Hash: Data] = .init()
        
        init(folderURL: URL) async throws {
            self.folderURL = folderURL
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try await loadPendingTransactionsFromDisk()
        }
    }
}

private extension Account.Outbox {
    func loadPendingTransactionsFromDisk() async throws {
        pendingTransactions.removeAll()
        let urls = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        for url in urls {
            let filename = url.lastPathComponent
            guard let hashData = try? Data(hexString: filename) else { continue }
            let data = try Data(contentsOf: url)
            let hash = Transaction.Hash(naturalOrder: hashData)
            pendingTransactions[hash] = data
        }
    }
}

extension Account.Outbox {
    func save(transactionData: Data) async throws -> Transaction.Hash {
        let hash = Transaction.Hash(naturalOrder: HASH256.hash(transactionData))
        let url = folderURL.appendingPathComponent(hash.naturalOrder.hexadecimalString)
        pendingTransactions[hash] = transactionData
        do {
            try transactionData.write(to: url)
        } catch {
            pendingTransactions.removeValue(forKey: hash)
            throw error
        }
        return hash
    }
    
    func remove(transactionHash: Transaction.Hash) async {
        let url = folderURL.appendingPathComponent(transactionHash.naturalOrder.hexadecimalString)
        try? fileManager.removeItem(at: url)
        pendingTransactions.removeValue(forKey: transactionHash)
    }
    
    func loadPendingTransactions() async -> [Transaction.Hash: Data] {
        pendingTransactions
    }
}

extension Account.Outbox {
    func purgeTransactions() async {
        guard let urls = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return }
        for url in urls { try? fileManager.removeItem(at: url) }
        pendingTransactions.removeAll()
    }
}

extension Account {
    func purgeOutbox() async {
        await outbox.purgeTransactions()
    }
}
