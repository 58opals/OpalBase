// Address+Book~UTXO~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Address.Book {
    public func refreshUTXOSet(fulcrum: Fulcrum) async throws {
        let operation = { [self] in
            var updatedUTXOs = [Transaction.Output.Unspent]()
            
            for entry in (receivingEntries + changeEntries) {
                let newUTXOs = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
                let orderedUTXOs = newUTXOs.map {
                    Transaction.Output.Unspent(value: $0.value,
                                               lockingScript: $0.lockingScript,
                                               previousTransactionHash: $0.previousTransactionHash,
                                               previousTransactionOutputIndex: $0.previousTransactionOutputIndex)
                }
                updatedUTXOs.append(contentsOf: orderedUTXOs)
            }
            
            clearUTXOs()
            addUTXOs(updatedUTXOs)
        }
        
        try await executeOrEnqueue(operation)
    }
}
