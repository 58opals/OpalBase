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
    func retryPendingTransactions(using gateway: Network.Gateway) async {
        guard let urls = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return }
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                let response = try await gateway.submit(data)
                guard !response.originalData.isEmpty else { continue }
                try fileManager.removeItem(at: url)
            } catch {
                continue
            }
        }
    }
    
    func purgeTransactions() async {
        guard let urls = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return }
        for url in urls { try? fileManager.removeItem(at: url) }
    }
}

extension Account {
    func retryOutbox() async {
        if let gateway = try? await fulcrumPool.acquireGateway() {
            await outbox.retryPendingTransactions(using: gateway)
        }
    }
    
    func purgeOutbox() async {
        await outbox.purgeTransactions()
    }
}
