// Account+Outbox.swift

import Foundation
import SwiftFulcrum

extension Account {
    public actor Outbox {
        private let folderURL: URL
        private let fileManager = FileManager.default
        
        init(folderURL: URL) throws {
            self.folderURL = folderURL
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
    }
}

extension Account.Outbox {
    func save(_ transactionData: Data) async throws {
        let hash = HASH256.hash(transactionData)
        let url = folderURL.appendingPathComponent(hash.hexadecimalString)
        try transactionData.write(to: url)
    }
    
    func remove(hash: Data) async {
        let url = folderURL.appendingPathComponent(hash.hexadecimalString)
        try? fileManager.removeItem(at: url)
    }
}
    
extension Account.Outbox {
    public func retry(using fulcrum: Fulcrum) async {
        guard let urls = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return }
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                let response = try await fulcrum.submit(method: .blockchain(.transaction(.broadcast(rawTransaction: data.hexadecimalString))),
                                                        responseType: Response.Result.Blockchain.Transaction.Broadcast.self)
                guard case .single = response else { continue }
                try fileManager.removeItem(at: url)
            } catch {
                continue
            }
        }
    }
    
    public func purge() async {
        guard let urls = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return }
        for url in urls { try? fileManager.removeItem(at: url) }
    }
}

extension Account {
    public func retryOutbox() async {
        guard let fulcrum = try? await fulcrumPool.getFulcrum() else { return }
        await outbox.retry(using: fulcrum)
    }

    public func purgeOutbox() async {
        await outbox.purge()
    }
}
