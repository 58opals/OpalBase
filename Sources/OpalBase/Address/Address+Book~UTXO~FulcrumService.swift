// Address+Book~UTXO~FulcrumService.swift

import Foundation

extension Address.Book {
    public func refreshUTXOSet(service: Network.FulcrumService) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            let entries = await receivingEntries + changeEntries
            
            let updatedUTXOs = try await withThrowingTaskGroup(of: [Transaction.Output.Unspent].self) { group in
                for entry in entries {
                    group.addTask {
                        try await service.unspentOutputs(for: entry.address)
                    }
                }
                
                var collected: [Transaction.Output.Unspent] = .init()
                for try await utxos in group {
                    collected.append(contentsOf: utxos)
                }
                return collected
            }
            
            await clearUTXOs()
            await addUTXOs(updatedUTXOs)
        }
        
        try await executeOrEnqueue(.refreshUTXOSet, operation: operation)
    }
}
