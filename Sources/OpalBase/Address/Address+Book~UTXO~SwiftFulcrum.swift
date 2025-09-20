// Address+Book~UTXO~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Address.Book {
    public func refreshUTXOSet(fulcrum: Fulcrum) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            let entries = await receivingEntries + changeEntries
            
            let updatedUTXOs = try await withThrowingTaskGroup(of: [Transaction.Output.Unspent].self) { group in
                for entry in entries {
                    group.addTask {
                        let newUTXOs = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
                        return newUTXOs.map {
                            Transaction.Output.Unspent(value: $0.value,
                                                       lockingScript: $0.lockingScript,
                                                       previousTransactionHash: $0.previousTransactionHash,
                                                       previousTransactionOutputIndex: $0.previousTransactionOutputIndex)
                        }
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
